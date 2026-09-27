begin;

create or replace function public.admin_set_central_pricing(
  p_valid_from date,
  p_rate_1_15_huf bigint,
  p_rate_over_15_to_60_huf bigint,
  p_rate_over_60_huf bigint,
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
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if p_valid_from is null then raise exception 'Az érvényesség kezdete kötelező.' using errcode='22004'; end if;
  if least(p_rate_1_15_huf, p_rate_over_15_to_60_huf, p_rate_over_60_huf) < 0 then
    raise exception 'Az óradíj nem lehet negatív.' using errcode='22023';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A módosítás indoka kötelező.' using errcode='22004'; end if;

  perform pg_advisory_xact_lock(hashtextextended('central_pricing', 0));
  select coalesce(jsonb_agg(to_jsonb(tier) order by tier.min_minutes), '[]'::jsonb) into v_before
  from public.pricing_tiers tier
  where p_valid_from between tier.valid_from and coalesce(tier.valid_to, 'infinity'::date);

  if exists (select 1 from public.pricing_tiers where valid_from = p_valid_from) then
    update public.pricing_tiers set hourly_rate_huf = case min_minutes
      when 60 then p_rate_1_15_huf when 901 then p_rate_over_15_to_60_huf when 3601 then p_rate_over_60_huf end
    where valid_from = p_valid_from and min_minutes in (60,901,3601);
  else
    update public.pricing_tiers set valid_to = p_valid_from - 1
    where valid_from < p_valid_from and p_valid_from <= coalesce(valid_to, 'infinity'::date);
    insert into public.pricing_tiers(min_minutes,max_minutes,hourly_rate_huf,valid_from,valid_to,created_by)
    select input.min_minutes,input.max_minutes,input.rate,p_valid_from,
      (select min(future.valid_from)-1 from public.pricing_tiers future
       where future.min_minutes=input.min_minutes and future.valid_from>p_valid_from),v_actor
    from (values
      (60,900,p_rate_1_15_huf),(901,3600,p_rate_over_15_to_60_huf),(3601,null::integer,p_rate_over_60_huf)
    ) input(min_minutes,max_minutes,rate);
  end if;

  select coalesce(jsonb_agg(to_jsonb(tier) order by tier.min_minutes), '[]'::jsonb) into v_after
  from public.pricing_tiers tier where tier.valid_from = p_valid_from;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'pricing.central_schedule_set','pricing_tiers',p_valid_from::text,v_before,v_after,btrim(p_reason),p_correlation_id);
end;
$$;

create or replace function public.admin_set_training_room_rate(
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
  v_room_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_next date;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if p_valid_from is null then raise exception 'Az érvényesség kezdete kötelező.' using errcode='22004'; end if;
  if p_hourly_rate_huf is null or p_hourly_rate_huf < 0 then raise exception 'Az óradíj nem lehet negatív.' using errcode='22023'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'A módosítás indoka kötelező.' using errcode='22004'; end if;
  select id into v_room_id from public.rooms where is_training_room and is_active order by display_order limit 1;
  if v_room_id is null then raise exception 'A Tréningterem nem található.' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended('training_room_rate:'||v_room_id::text,0));
  select to_jsonb(rate) into v_before from public.special_room_rates rate
  where rate.room_id=v_room_id and rate.use_type='group'
    and p_valid_from between rate.valid_from and coalesce(rate.valid_to,'infinity'::date)
  order by rate.valid_from desc limit 1;
  if exists (select 1 from public.special_room_rates where room_id=v_room_id and use_type='group' and valid_from=p_valid_from) then
    update public.special_room_rates set hourly_rate_huf=p_hourly_rate_huf
    where room_id=v_room_id and use_type='group' and valid_from=p_valid_from;
  else
    update public.special_room_rates set valid_to=p_valid_from-1
    where room_id=v_room_id and use_type='group' and valid_from<p_valid_from
      and p_valid_from<=coalesce(valid_to,'infinity'::date);
    select min(valid_from) into v_next from public.special_room_rates
    where room_id=v_room_id and use_type='group' and valid_from>p_valid_from;
    insert into public.special_room_rates(room_id,use_type,hourly_rate_huf,valid_from,valid_to,created_by)
    values(v_room_id,'group',p_hourly_rate_huf,p_valid_from,case when v_next is null then null else v_next-1 end,v_actor);
  end if;
  select to_jsonb(rate) into v_after from public.special_room_rates rate
  where rate.room_id=v_room_id and rate.use_type='group' and rate.valid_from=p_valid_from;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'pricing.training_room_rate_set','special_room_rate',v_room_id::text,v_before,v_after,btrim(p_reason),p_correlation_id);
end;
$$;

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