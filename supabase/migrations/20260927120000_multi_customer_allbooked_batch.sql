begin;

create or replace function public.admin_import_allbooked_batch(
  p_actor_id uuid,
  p_customers jsonb,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_total_bookings integer := 0;
  v_total_created integer := 0;
  v_total_existing integer := 0;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin' and is_active) then
    raise exception 'Az importot csak aktív admin futtathatja.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_customers) <> 'array' or jsonb_array_length(p_customers) not between 1 and 500 then
    raise exception 'A batch import 1 és 500 közötti felhasználót tartalmazhat.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_customers) item
    where jsonb_typeof(item) <> 'object'
      or not item ?& array['userId','email','firstName','lastName','phone','accessGroupNames','bookings']
      or item - array['userId','email','firstName','lastName','phone','accessGroupNames','bookings'] <> '{}'::jsonb
  ) then
    raise exception 'A batch ügyfél-payload tiltott vagy hiányzó mezőt tartalmaz.' using errcode = '22023';
  end if;
  if (select count(distinct lower(item ->> 'email')) from jsonb_array_elements(p_customers) item) <> jsonb_array_length(p_customers) then
    raise exception 'A batch importban az e-mail címek nem egyediek.' using errcode = '22023';
  end if;

  for v_customer in
    select item from jsonb_array_elements(p_customers) item order by lower(item ->> 'email')
  loop
    v_result := public.admin_import_allbooked_customer(
      p_actor_id,
      (v_customer ->> 'userId')::uuid,
      v_customer ->> 'email',
      v_customer ->> 'firstName',
      v_customer ->> 'lastName',
      nullif(v_customer ->> 'phone', ''),
      array(select jsonb_array_elements_text(v_customer -> 'accessGroupNames')),
      v_customer -> 'bookings',
      p_correlation_id
    );
    if not coalesce((v_result ->> 'valid')::boolean, false) then
      raise exception 'Az AllBooked batch import egyik ügyfél-reconciliationje sikertelen.' using errcode = 'P0001';
    end if;
    v_results := v_results || jsonb_build_array(v_result);
    v_total_bookings := v_total_bookings + coalesce((v_result ->> 'bookings')::integer, 0);
    v_total_created := v_total_created + coalesce((v_result ->> 'created')::integer, 0);
    v_total_existing := v_total_existing + coalesce((v_result ->> 'existing')::integer, 0);
  end loop;

  return jsonb_build_object(
    'valid', jsonb_array_length(v_results) = jsonb_array_length(p_customers),
    'users', jsonb_array_length(v_results),
    'bookings', v_total_bookings,
    'created', v_total_created,
    'existing', v_total_existing,
    'customers', v_results
  );
end;
$$;

revoke all on function public.admin_import_allbooked_batch(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.admin_import_allbooked_batch(uuid,jsonb,uuid) to service_role;

comment on function public.admin_import_allbooked_batch(uuid,jsonb,uuid) is
  'Atomic multi-customer AllBooked DB import. All customer imports share one transaction; any failure rolls back the entire database batch. Service role only.';

commit;
