begin;

create or replace function public.update_own_profile_data(
  p_phone text,
  p_customer_type text,
  p_billing_name text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_street text,
  p_billing_house_number text,
  p_tax_number text,
  p_correlation_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_customer_type text := lower(btrim(coalesce(p_customer_type, '')));
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  select * into v_actor from public.profiles where id=auth.uid() and is_active for update;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  if v_actor.onboarding_completed_at is null and v_actor.role <> 'admin' then
    raise exception 'Az első adatkitöltést előbb be kell fejezni.' using errcode='P0001';
  end if;
  if nullif(btrim(coalesce(p_phone,'')),'') is null
    or nullif(btrim(coalesce(p_billing_name,'')),'') is null
    or nullif(btrim(coalesce(p_billing_postal_code,'')),'') is null
    or nullif(btrim(coalesce(p_billing_city,'')),'') is null
    or nullif(btrim(coalesce(p_billing_street,'')),'') is null
    or nullif(btrim(coalesce(p_billing_house_number,'')),'') is null then
    raise exception 'A telefonszám, a számlázási név és a teljes számlázási cím kitöltése kötelező.' using errcode='P0001';
  end if;
  if v_customer_type not in ('private','business') then raise exception 'Érvénytelen ügyféltípus.' using errcode='22023'; end if;
  if v_customer_type='business' and nullif(btrim(coalesce(p_tax_number,'')),'') is null then
    raise exception 'Vállalkozói számlázás esetén az adószám megadása kötelező.' using errcode='P0001';
  end if;

  v_before := to_jsonb(v_actor);
  update public.profiles
  set phone=btrim(p_phone),
      customer_type=v_customer_type,
      billing_name=btrim(p_billing_name),
      billing_postal_code=btrim(p_billing_postal_code),
      billing_city=btrim(p_billing_city),
      billing_street=btrim(p_billing_street),
      billing_house_number=btrim(p_billing_house_number),
      tax_number=case when v_customer_type='business' then btrim(p_tax_number) else null end,
      updated_at=clock_timestamp()
  where id=v_actor.id;

  select to_jsonb(profile) into v_after from public.profiles profile where profile.id=v_actor.id;
  if v_before is distinct from v_after then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,correlation_id)
    values(v_actor.id,'profile.self_updated','profile',v_actor.id::text,v_before,v_after,p_correlation_id);
  end if;
end;
$$;

grant execute on function public.update_own_profile_data(text,text,text,text,text,text,text,text,uuid) to authenticated;

commit;
