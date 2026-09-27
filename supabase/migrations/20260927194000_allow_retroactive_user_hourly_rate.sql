begin;
create or replace function public.admin_set_user_hourly_rate(
  p_user_id uuid,
  p_hourly_rate_huf bigint,
  p_valid_from date,
  p_reason text,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_existing public.user_price_overrides%rowtype;
  v_new_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_next date;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'A felhasználó nem található.' using errcode='P0001'; end if;
  if p_valid_from is null then raise exception 'Az érvényesség kezdete kötelező.' using errcode='22004'; end if;
  if p_hourly_rate_huf is not null and p_hourly_rate_huf < 0 then raise exception 'Az óradíj nem lehet negatív.' using errcode='22023'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A módosítás indoka kötelező.' using errcode='22004'; end if;
  perform pg_advisory_xact_lock(hashtextextended('user_rate:'||p_user_id::text,0));
  select * into v_existing from public.user_price_overrides
  where user_id=p_user_id and p_valid_from between valid_from and coalesce(valid_to,'infinity'::date)
  order by valid_from desc limit 1 for update;
  v_before := to_jsonb(v_existing);

  if p_hourly_rate_huf is null then
    if v_existing.id is null then return; end if;
    if v_existing.valid_from = p_valid_from then
      delete from public.user_price_overrides where id=v_existing.id;
      v_after := null;
    else
      update public.user_price_overrides set valid_to=p_valid_from-1 where id=v_existing.id;
      select to_jsonb(override) into v_after from public.user_price_overrides override where override.id=v_existing.id;
    end if;
  elsif v_existing.id is not null and v_existing.valid_from=p_valid_from then
    update public.user_price_overrides set hourly_rate_huf=p_hourly_rate_huf,reason=btrim(p_reason)
    where id=v_existing.id;
    select to_jsonb(override) into v_after from public.user_price_overrides override where override.id=v_existing.id;
  else
    if v_existing.id is not null then
      update public.user_price_overrides set valid_to=p_valid_from-1 where id=v_existing.id;
    end if;
    select min(valid_from) into v_next from public.user_price_overrides where user_id=p_user_id and valid_from>p_valid_from;
    insert into public.user_price_overrides(user_id,hourly_rate_huf,valid_from,valid_to,reason,created_by)
    values(p_user_id,p_hourly_rate_huf,p_valid_from,case when v_next is null then null else v_next-1 end,btrim(p_reason),v_actor)
    returning id into v_new_id;
    select to_jsonb(override) into v_after from public.user_price_overrides override where override.id=v_new_id;
  end if;

  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'pricing.user_hourly_rate_set','user_price_override',p_user_id::text,v_before,v_after,btrim(p_reason),p_correlation_id);
end;
$$;

commit;
