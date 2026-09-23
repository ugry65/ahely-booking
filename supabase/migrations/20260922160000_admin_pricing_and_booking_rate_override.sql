begin;

create type public.applied_rate_source as enum (
  'booking_override',
  'user_override',
  'central_tier',
  'training_room'
);

alter table public.bookings
  add column hourly_rate_override_huf bigint
    check (hourly_rate_override_huf is null or hourly_rate_override_huf >= 0),
  add column hourly_rate_override_set_by uuid references public.profiles(id) on delete restrict,
  add column hourly_rate_override_set_at timestamptz,
  add column hourly_rate_override_reason text,
  add constraint bookings_rate_override_consistency check (
    (hourly_rate_override_huf is null
      and hourly_rate_override_set_by is null
      and hourly_rate_override_set_at is null
      and hourly_rate_override_reason is null)
    or
    (hourly_rate_override_huf is not null
      and hourly_rate_override_set_by is not null
      and hourly_rate_override_set_at is not null
      and nullif(btrim(hourly_rate_override_reason), '') is not null)
  );

create table public.booking_pricing_requests(
  idempotency_key uuid primary key,
  operation text not null,
  hourly_rate_override_huf bigint check(hourly_rate_override_huf is null or hourly_rate_override_huf>=0),
  override_reason text,
  created_at timestamptz not null default now()
);
alter table public.booking_pricing_requests enable row level security;

alter table public.settlement_revisions
  add column pricing_breakdown jsonb not null default '[]'::jsonb;

alter table public.settlement_booking_lines
  add column rate_source public.applied_rate_source,
  add column booking_start_at timestamptz,
  add column booking_end_at timestamptz,
  add column room_id uuid references public.rooms(id) on delete restrict,
  add column room_name text;

update public.settlement_booking_lines
set rate_source = case pricing_mode
  when 'fixed_user' then 'user_override'::public.applied_rate_source
  when 'special_room' then 'training_room'::public.applied_rate_source
  else 'central_tier'::public.applied_rate_source
end;

update public.settlement_booking_lines line
set booking_start_at=booking.start_at,
    booking_end_at=booking.end_at,
    room_id=booking.room_id,
    room_name=room.name
from public.bookings booking
join public.rooms room on room.id=booking.room_id
where booking.id=line.booking_id;

alter table public.settlement_booking_lines
  alter column rate_source set not null,
  alter column booking_start_at set not null,
  alter column booking_end_at set not null,
  alter column room_id set not null,
  alter column room_name set not null;

-- The approved rates start on the next full month after approval. These
-- deployment-time financial changes are recorded as system migration audit
-- events; actor_user_id is intentionally null because no application user is
-- acting during a database migration.
do $$
declare
  v_before jsonb;
  v_after jsonb;
  v_training_room_id uuid;
  v_training_before jsonb;
  v_training_after jsonb;
  v_next_training_rate date;
begin
  select coalesce(jsonb_agg(to_jsonb(tier) order by tier.min_minutes), '[]'::jsonb)
  into v_before
  from public.pricing_tiers tier
  where date '2026-10-01' between tier.valid_from and coalesce(tier.valid_to, 'infinity'::date);

  update public.pricing_tiers
  set valid_to = date '2026-09-30'
  where valid_from < date '2026-10-01'
    and date '2026-10-01' <= coalesce(valid_to, 'infinity'::date);

  insert into public.pricing_tiers(min_minutes,max_minutes,hourly_rate_huf,valid_from,valid_to)
  values
    (60,900,2500,date '2026-10-01',null),
    (901,3600,1900,date '2026-10-01',null),
    (3601,null,1700,date '2026-10-01',null);

  select jsonb_agg(to_jsonb(tier) order by tier.min_minutes)
  into v_after from public.pricing_tiers tier where tier.valid_from=date '2026-10-01';
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(null,'pricing.central_schedule_migrated','pricing_tiers','2026-10-01',v_before,v_after,
    'GitHub #178 jóváhagyott központi díjszabás',gen_random_uuid());

  select room.id into v_training_room_id
  from public.rooms room where room.is_training_room and room.is_active
  order by room.display_order,room.id limit 1;
  if v_training_room_id is null then
    raise exception 'A Tréningterem nem található; az 5 000 Ft-os tarifa nem telepíthető.' using errcode='P0001';
  end if;
  select to_jsonb(rate) into v_training_before
  from public.special_room_rates rate
  where rate.room_id=v_training_room_id and rate.use_type='group'
    and date '2026-10-01' between rate.valid_from and coalesce(rate.valid_to,'infinity'::date)
  order by rate.valid_from desc limit 1;
  update public.special_room_rates set valid_to=date '2026-09-30'
  where room_id=v_training_room_id and use_type='group' and valid_from<date '2026-10-01'
    and date '2026-10-01'<=coalesce(valid_to,'infinity'::date);
  select min(valid_from) into v_next_training_rate from public.special_room_rates
  where room_id=v_training_room_id and use_type='group' and valid_from>date '2026-10-01';
  if exists(select 1 from public.special_room_rates
    where room_id=v_training_room_id and use_type='group' and valid_from=date '2026-10-01') then
    update public.special_room_rates set hourly_rate_huf=5000
    where room_id=v_training_room_id and use_type='group' and valid_from=date '2026-10-01';
  else
    insert into public.special_room_rates(room_id,use_type,hourly_rate_huf,valid_from,valid_to)
    values(v_training_room_id,'group',5000,date '2026-10-01',
      case when v_next_training_rate is null then null else v_next_training_rate-1 end);
  end if;
  select to_jsonb(rate) into v_training_after from public.special_room_rates rate
  where rate.room_id=v_training_room_id and rate.use_type='group' and rate.valid_from=date '2026-10-01';
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(null,'pricing.training_room_rate_migrated','special_room_rate',v_training_room_id::text,
    v_training_before,v_training_after,'GitHub #178 jóváhagyott Tréningterem alapdíj',gen_random_uuid());
end;
$$;

create or replace function public.prevent_settlement_snapshot_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'A megőrzött elszámolási snapshot nem módosítható.' using errcode = '42501';
end;
$$;

create or replace function public.claim_admin_pricing_request(
  p_idempotency_key uuid,p_operation text,p_hourly_rate_override_huf bigint,p_override_reason text
)
returns void language plpgsql security definer set search_path=''
as $$
declare v_request public.booking_pricing_requests%rowtype; v_reason text:=nullif(btrim(p_override_reason),'');
begin
  if p_idempotency_key is null then raise exception 'A kérésazonosító kötelező.' using errcode='22004'; end if;
  if nullif(btrim(p_operation),'') is null then raise exception 'A pricing művelet azonosítója kötelező.' using errcode='22004'; end if;
  if p_hourly_rate_override_huf is not null and p_hourly_rate_override_huf<0 then raise exception 'Az óradíj nem lehet negatív.' using errcode='22023'; end if;
  insert into public.booking_pricing_requests(idempotency_key,operation,hourly_rate_override_huf,override_reason)
  values(p_idempotency_key,btrim(p_operation),p_hourly_rate_override_huf,v_reason)
  on conflict(idempotency_key) do nothing;
  select * into v_request from public.booking_pricing_requests where idempotency_key=p_idempotency_key;
  if v_request.operation<>btrim(p_operation)
    or v_request.hourly_rate_override_huf is distinct from p_hourly_rate_override_huf
    or v_request.override_reason is distinct from v_reason
  then
    raise exception 'Ezt a kérésazonosítót már más árazási adatokkal használták.' using errcode='P0001';
  end if;
end;
$$;

create trigger settlement_revisions_immutable
before update or delete on public.settlement_revisions
for each row execute function public.prevent_settlement_snapshot_mutation();

create trigger settlement_booking_lines_immutable
before update or delete on public.settlement_booking_lines
for each row execute function public.prevent_settlement_snapshot_mutation();

create or replace function public.month_normal_minutes(
  p_user_id uuid,
  p_month date,
  p_excluded_booking_id uuid default null,
  p_additional_minutes integer default 0,
  p_additional_is_special boolean default false
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(
    (extract(epoch from (booking.end_at - booking.start_at)) / 60)::integer
  ) filter (
    where not (room.is_training_room and booking.use_type = 'group')
  ), 0)::integer
  + case when p_additional_is_special then 0 else greatest(coalesce(p_additional_minutes, 0), 0) end
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id
  where booking.user_id = p_user_id
    and booking.status = 'active'
    and booking.id is distinct from p_excluded_booking_id
    and (booking.start_at at time zone 'Europe/Budapest')::date >= p_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (p_month + interval '1 month')::date;
$$;

create or replace function public.resolve_booking_applied_rate(
  p_booking_id uuid,
  p_month_normal_minutes integer
)
returns table (
  rate_source public.applied_rate_source,
  pricing_rule_id uuid,
  hourly_rate_huf bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings%rowtype;
  v_service_date date;
  v_is_training_group boolean;
begin
  select booking,
         (booking.start_at at time zone 'Europe/Budapest')::date,
         room.is_training_room and booking.use_type = 'group'
  into v_booking, v_service_date, v_is_training_group
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id
  where booking.id = p_booking_id;

  if not found then
    raise exception 'A foglalás nem található.' using errcode = 'P0001';
  end if;

  if v_booking.hourly_rate_override_huf is not null then
    return query select
      'booking_override'::public.applied_rate_source,
      null::uuid,
      v_booking.hourly_rate_override_huf;
    return;
  end if;

  return query
  select 'user_override'::public.applied_rate_source, override.id, override.hourly_rate_huf
  from public.user_price_overrides override
  where override.user_id = v_booking.user_id
    and v_service_date between override.valid_from and coalesce(override.valid_to, 'infinity'::date)
  order by override.valid_from desc
  limit 1;
  if found then return; end if;

  if v_is_training_group then
    return query
    select 'training_room'::public.applied_rate_source, rate.id, rate.hourly_rate_huf
    from public.special_room_rates rate
    where rate.room_id = v_booking.room_id
      and rate.use_type = v_booking.use_type
      and v_service_date between rate.valid_from and coalesce(rate.valid_to, 'infinity'::date)
    order by rate.valid_from desc
    limit 1;
    if not found then
      raise exception 'Nincs érvényes Tréningterem csoportos óradíj.' using errcode = 'P0001';
    end if;
    return;
  end if;

  return query
  select 'central_tier'::public.applied_rate_source, tier.id, tier.hourly_rate_huf
  from public.pricing_tiers tier
  where p_month_normal_minutes between tier.min_minutes and coalesce(tier.max_minutes, 2147483647)
    and v_service_date between tier.valid_from and coalesce(tier.valid_to, 'infinity'::date)
  order by tier.min_minutes desc, tier.valid_from desc
  limit 1;
  if not found then
    raise exception 'Nincs érvényes központi díjsáv a havi óraszámhoz.' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.calculate_monthly_pricing(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  normal_minutes integer,
  special_minutes integer,
  calculated_due_huf bigint,
  pricing_breakdown jsonb,
  calculation_input_hash text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month_normal_minutes integer;
  v_normal_minutes integer := 0;
  v_special_minutes integer := 0;
  v_due bigint := 0;
  v_breakdown jsonb := '[]'::jsonb;
  v_booking record;
  v_rate record;
  v_minutes integer;
  v_amount bigint;
  v_digest text := '';
begin
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  v_month_normal_minutes := public.month_normal_minutes(p_user_id, p_settlement_month);

  for v_booking in
    select booking.id, booking.updated_at, booking.start_at, booking.end_at,
      booking.room_id, room.name as room_name,
      room.is_training_room and booking.use_type = 'group' as is_special,
      (extract(epoch from (booking.end_at - booking.start_at)) / 60)::integer as duration_minutes
    from public.bookings booking
    join public.rooms room on room.id = booking.room_id
    where booking.user_id = p_user_id
      and booking.status = 'active'
      and (booking.start_at at time zone 'Europe/Budapest')::date >= p_settlement_month
      and (booking.start_at at time zone 'Europe/Budapest')::date < (p_settlement_month + interval '1 month')::date
    order by booking.start_at, booking.id
  loop
    v_minutes := v_booking.duration_minutes;
    select * into v_rate
    from public.resolve_booking_applied_rate(v_booking.id, v_month_normal_minutes);
    v_amount := round(v_minutes::numeric * v_rate.hourly_rate_huf / 60)::bigint;
    v_due := v_due + v_amount;
    if v_booking.is_special then
      v_special_minutes := v_special_minutes + v_minutes;
    else
      v_normal_minutes := v_normal_minutes + v_minutes;
    end if;
    v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
      'booking_id', v_booking.id,
      'booking_start_at', v_booking.start_at,
      'booking_end_at', v_booking.end_at,
      'room_id', v_booking.room_id,
      'room_name', v_booking.room_name,
      'duration_minutes', v_minutes,
      'rate_source', v_rate.rate_source,
      'pricing_rule_id', v_rate.pricing_rule_id,
      'hourly_rate_huf', v_rate.hourly_rate_huf,
      'amount_huf', v_amount
    ));
    v_digest := v_digest || '|' || v_booking.id::text || ':' || v_booking.updated_at::text || ':'
      || v_rate.rate_source::text || ':' || coalesce(v_rate.pricing_rule_id::text, '') || ':'
      || v_rate.hourly_rate_huf::text || ':' || v_minutes::text || ':'
      || v_booking.start_at::text || ':' || v_booking.end_at::text || ':'
      || v_booking.room_id::text || ':' || v_booking.room_name;
  end loop;

  return query select
    p_user_id,
    p_settlement_month,
    v_normal_minutes,
    v_special_minutes,
    v_due,
    v_breakdown,
    encode(extensions.digest(p_user_id::text || '|' || p_settlement_month::text || v_digest, 'sha256'), 'hex');
end;
$$;

create or replace function public.admin_calculate_monthly_pricing(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  normal_minutes integer,
  special_minutes integer,
  calculated_due_huf bigint,
  pricing_breakdown jsonb,
  calculation_input_hash text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();
  return query select * from public.calculate_monthly_pricing(p_user_id, p_settlement_month);
end;
$$;

create or replace function public.admin_pricing_quote(
  p_user_id uuid,
  p_room_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_booking_id uuid default null,
  p_hourly_rate_override_huf bigint default null
)
returns table (
  rate_source public.applied_rate_source,
  hourly_rate_huf bigint,
  projected_month_normal_minutes integer,
  amount_huf bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_service_date date;
  v_month date;
  v_minutes integer;
  v_is_special boolean;
  v_projected integer;
  v_rate bigint;
  v_source public.applied_rate_source;
begin
  perform public.require_active_admin();
  if p_user_id is null or p_room_id is null or p_start_at is null or p_end_at is null or p_use_type is null then
    raise exception 'A díjelőnézet kötelező adatai hiányoznak.' using errcode = '22004';
  end if;
  if p_end_at <= p_start_at then
    raise exception 'A befejezésnek a kezdés után kell lennie.' using errcode = '22023';
  end if;
  if p_hourly_rate_override_huf is not null and p_hourly_rate_override_huf < 0 then
    raise exception 'Az óradíj nem lehet negatív.' using errcode = '22023';
  end if;
  select room.is_training_room and p_use_type = 'group'
  into v_is_special
  from public.rooms room where room.id = p_room_id and room.is_active;
  if not found then raise exception 'A helyiség nem található.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and is_active) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;

  v_service_date := (p_start_at at time zone 'Europe/Budapest')::date;
  v_month := date_trunc('month', v_service_date)::date;
  v_minutes := (extract(epoch from (p_end_at - p_start_at)) / 60)::integer;
  if p_booking_id is not null and not exists(
    select 1 from public.bookings booking where booking.id=p_booking_id and booking.user_id=p_user_id
      and date_trunc('month',(booking.start_at at time zone 'Europe/Budapest')::date)::date=v_month
  ) then
    raise exception 'A kizárt foglalás nem ehhez a userhez és hónaphoz tartozik.' using errcode='22023';
  end if;
  v_projected := public.month_normal_minutes(p_user_id, v_month, p_booking_id, v_minutes, v_is_special);

  if p_hourly_rate_override_huf is not null then
    v_source := 'booking_override'; v_rate := p_hourly_rate_override_huf;
  else
    select override.hourly_rate_huf into v_rate
    from public.user_price_overrides override
    where override.user_id = p_user_id
      and v_service_date between override.valid_from and coalesce(override.valid_to, 'infinity'::date)
    order by override.valid_from desc limit 1;
    if found then
      v_source := 'user_override';
    elsif v_is_special then
      select rate.hourly_rate_huf into v_rate
      from public.special_room_rates rate
      where rate.room_id = p_room_id and rate.use_type = p_use_type
        and v_service_date between rate.valid_from and coalesce(rate.valid_to, 'infinity'::date)
      order by rate.valid_from desc limit 1;
      if not found then raise exception 'Nincs érvényes Tréningterem csoportos óradíj.' using errcode = 'P0001'; end if;
      v_source := 'training_room';
    else
      select tier.hourly_rate_huf into v_rate
      from public.pricing_tiers tier
      where v_projected between tier.min_minutes and coalesce(tier.max_minutes, 2147483647)
        and v_service_date between tier.valid_from and coalesce(tier.valid_to, 'infinity'::date)
      order by tier.min_minutes desc, tier.valid_from desc limit 1;
      if not found then raise exception 'Nincs érvényes központi díjsáv.' using errcode = 'P0001'; end if;
      v_source := 'central_tier';
    end if;
  end if;

  return query select v_source, v_rate, v_projected,
    round(v_minutes::numeric * v_rate / 60)::bigint;
end;
$$;

create or replace function public.admin_list_pricing_rules()
returns table (
  rule_type text,
  rule_id uuid,
  min_minutes integer,
  max_minutes integer,
  room_id uuid,
  room_name text,
  use_type public.booking_use_type,
  hourly_rate_huf bigint,
  valid_from date,
  valid_to date
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();
  return query
    select 'central_tier'::text, tier.id, tier.min_minutes, tier.max_minutes,
      null::uuid, null::text, null::public.booking_use_type,
      tier.hourly_rate_huf, tier.valid_from, tier.valid_to
    from public.pricing_tiers tier
    union all
    select 'training_room'::text, rate.id, null::integer, null::integer,
      room.id, room.name, rate.use_type, rate.hourly_rate_huf, rate.valid_from, rate.valid_to
    from public.special_room_rates rate
    join public.rooms room on room.id = rate.room_id
    order by 1, 9 desc, 3 nulls last;
end;
$$;

create or replace function public.admin_list_user_price_overrides(p_user_id uuid default null)
returns table (
  id uuid,
  user_id uuid,
  hourly_rate_huf bigint,
  valid_from date,
  valid_to date,
  reason text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();
  return query select override.id, override.user_id, override.hourly_rate_huf,
    override.valid_from, override.valid_to, override.reason, override.created_at
  from public.user_price_overrides override
  where p_user_id is null or override.user_id = p_user_id
  order by override.user_id, override.valid_from desc;
end;
$$;

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
  if p_valid_from is null or p_valid_from <= timezone('Europe/Budapest',now())::date then
    raise exception 'Az új központi díjszabás legkorábban holnaptól lehet érvényes.' using errcode='22023';
  end if;
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
  if p_valid_from is null or p_valid_from <= timezone('Europe/Budapest',now())::date then
    raise exception 'Az új Tréningterem-díj legkorábban holnaptól lehet érvényes.' using errcode='22023';
  end if;
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
  if p_valid_from is null or p_valid_from <= timezone('Europe/Budapest',now())::date then
    raise exception 'Az új user díjazás legkorábban holnaptól lehet érvényes.' using errcode='22023';
  end if;
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

create or replace function public.admin_set_booking_hourly_rate_override(
  p_booking_id uuid,
  p_hourly_rate_huf bigint,
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
  v_booking public.bookings%rowtype;
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if p_hourly_rate_huf is not null and p_hourly_rate_huf < 0 then raise exception 'Az óradíj nem lehet negatív.' using errcode='22023'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'active' then raise exception 'Csak aktív foglalás díja módosítható.' using errcode='P0001'; end if;
  if v_booking.start_at <= now() then raise exception 'Múltbeli vagy megkezdett foglalás díja nem módosítható.' using errcode='P0001'; end if;
  if v_booking.hourly_rate_override_huf is not distinct from p_hourly_rate_huf then return; end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'A díjmódosítás indoka kötelező.' using errcode='22004'; end if;
  v_before := jsonb_build_object('hourly_rate_override_huf',v_booking.hourly_rate_override_huf,'set_by',v_booking.hourly_rate_override_set_by,'set_at',v_booking.hourly_rate_override_set_at,'reason',v_booking.hourly_rate_override_reason);
  update public.bookings set
    hourly_rate_override_huf=p_hourly_rate_huf,
    hourly_rate_override_set_by=case when p_hourly_rate_huf is null then null else v_actor end,
    hourly_rate_override_set_at=case when p_hourly_rate_huf is null then null else clock_timestamp() end,
    hourly_rate_override_reason=case when p_hourly_rate_huf is null then null else btrim(p_reason) end,
    updated_at=clock_timestamp()
  where id=p_booking_id;
  select jsonb_build_object('hourly_rate_override_huf',booking.hourly_rate_override_huf,'set_by',booking.hourly_rate_override_set_by,'set_at',booking.hourly_rate_override_set_at,'reason',booking.hourly_rate_override_reason)
  into v_after from public.bookings booking where booking.id=p_booking_id;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'pricing.booking_hourly_rate_override_set','booking',p_booking_id::text,v_before,v_after,btrim(p_reason),p_correlation_id);
end;
$$;

create or replace function public.admin_create_booking_with_pricing(
  p_room_id uuid,p_user_id uuid,p_start_at timestamptz,p_end_at timestamptz,
  p_use_type public.booking_use_type,p_note text,p_idempotency_key uuid,p_booking_title text,
  p_hourly_rate_override_huf bigint,p_override_reason text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_id uuid;
begin
  perform public.require_active_admin();
  perform public.claim_admin_pricing_request(p_idempotency_key,'booking_create',p_hourly_rate_override_huf,p_override_reason);
  v_id := public.create_booking(p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,p_booking_title);
  if p_hourly_rate_override_huf is not null then
    perform public.admin_set_booking_hourly_rate_override(v_id,p_hourly_rate_override_huf,p_override_reason,p_idempotency_key);
  end if;
  return v_id;
end;
$$;

create or replace function public.admin_update_booking_with_pricing(
  p_booking_id uuid,p_expected_updated_at timestamptz,p_room_id uuid,p_start_at timestamptz,
  p_end_at timestamptz,p_use_type public.booking_use_type,p_note text,p_idempotency_key uuid,
  p_booking_title text,p_hourly_rate_override_huf bigint,p_override_reason text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_id uuid;
begin
  perform public.require_active_admin();
  perform public.claim_admin_pricing_request(p_idempotency_key,'booking_update',p_hourly_rate_override_huf,p_override_reason);
  v_id := public.update_booking(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,p_booking_title);
  perform public.admin_set_booking_hourly_rate_override(v_id,p_hourly_rate_override_huf,p_override_reason,p_idempotency_key);
  return v_id;
end;
$$;

create or replace function public.admin_update_booking_scope_with_pricing(
  p_booking_id uuid,p_scope text,p_expected_updated_at timestamptz,p_room_id uuid,
  p_start_at timestamptz,p_end_at timestamptz,p_use_type public.booking_use_type,
  p_note text,p_idempotency_key uuid,p_booking_title text,p_apply_rate_override boolean,
  p_hourly_rate_override_huf bigint,p_override_reason text
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer;
begin
  perform public.require_active_admin();
  if coalesce(p_apply_rate_override,false) and p_scope<>'occurrence' then
    raise exception 'Foglalásszintű óradíj csak egyetlen alkalomra módosítható.' using errcode='22023';
  end if;
  perform public.claim_admin_pricing_request(
    p_idempotency_key,'booking_update_scope:'||p_scope,
    case when coalesce(p_apply_rate_override,false) then p_hourly_rate_override_huf else null end,
    case when coalesce(p_apply_rate_override,false) then p_override_reason else null end
  );
  v_count:=public.update_booking_scope(p_booking_id,p_scope,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,p_booking_title);
  if coalesce(p_apply_rate_override,false) then
    perform public.admin_set_booking_hourly_rate_override(p_booking_id,p_hourly_rate_override_huf,p_override_reason,p_idempotency_key);
  end if;
  return v_count;
end;
$$;

create or replace function public.admin_create_booking_series_with_pricing(
  p_room_id uuid,p_user_id uuid,p_first_start_at timestamptz,p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency,p_ends_on date,p_occurrence_count integer,
  p_exception_dates date[],p_conflict_policy public.conflict_policy,p_use_type public.booking_use_type,
  p_note text,p_idempotency_key uuid,p_booking_title text,p_hourly_rate_override_huf bigint,
  p_override_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_result jsonb; v_series_id uuid; v_booking_id uuid;
begin
  perform public.require_active_admin();
  perform public.claim_admin_pricing_request(p_idempotency_key,'booking_series_create',p_hourly_rate_override_huf,p_override_reason);
  v_result := public.create_booking_series(p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key,p_booking_title);
  if p_hourly_rate_override_huf is not null then
    v_series_id := (v_result->>'series_id')::uuid;
    for v_booking_id in select id from public.bookings where series_id=v_series_id and status='active' order by start_at,id
    loop
      perform public.admin_set_booking_hourly_rate_override(v_booking_id,p_hourly_rate_override_huf,p_override_reason,p_idempotency_key);
    end loop;
  end if;
  return v_result;
end;
$$;

drop function public.list_calendar_booking_management(timestamptz,timestamptz);
create function public.list_calendar_booking_management(p_start_at timestamptz,p_end_at timestamptz)
returns table(
  booking_id uuid,note text,booking_title text,series_id uuid,updated_at timestamptz,can_manage boolean,
  user_id uuid,hourly_rate_override_huf bigint,hourly_rate_override_reason text
)
language plpgsql stable security definer set search_path=''
as $$
declare v_actor public.profiles%rowtype;
begin
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode='22023'; end if;
  if p_end_at-p_start_at>interval '62 days' then raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode='22023'; end if;
  select * into v_actor from public.profiles where id=auth.uid() and is_active;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  return query select booking.id,booking.note,booking.booking_title,booking.series_id,booking.updated_at,true,
    booking.user_id,
    case when v_actor.role='admin' then booking.hourly_rate_override_huf else null end,
    case when v_actor.role='admin' then booking.hourly_rate_override_reason else null end
  from public.bookings booking
  join public.rooms room on room.id=booking.room_id and room.is_active
  where booking.status='active' and booking.start_at<p_end_at and booking.end_at>p_start_at
    and (v_actor.role='admin' or booking.user_id=v_actor.id)
  order by booking.start_at,booking.id;
end;
$$;

create or replace function public.admin_create_monthly_settlement_revision(
  p_user_id uuid,
  p_settlement_month date,
  p_reason text,
  p_correlation_id uuid
)
returns table(settlement_id uuid,revision_id uuid,revision_number integer,calculated_due_huf bigint)
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=public.require_active_admin(); v_settlement_id uuid; v_revision_id uuid;
  v_revision_number integer; v_calc record; v_booking record; v_line jsonb; v_source public.applied_rate_source;
  v_mode public.pricing_mode; v_rule_id uuid; v_rate bigint; v_amount bigint; v_line_total bigint; v_line_minutes integer;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'Az elszámolási revision indoka kötelező.' using errcode='22004'; end if;
  if p_settlement_month is null or p_settlement_month<>date_trunc('month',p_settlement_month)::date then raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode='22023'; end if;
  if p_settlement_month>=date_trunc('month',timezone('Europe/Budapest',now()))::date then raise exception 'Csak már befejeződött hónapról készíthető végleges elszámolási revision.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text||':'||p_settlement_month::text,0));
  insert into public.monthly_settlements(user_id,settlement_month) values(p_user_id,p_settlement_month)
  on conflict(user_id,settlement_month) do update set updated_at=now()
  returning id into v_settlement_id;
  select * into v_calc from public.calculate_monthly_pricing(p_user_id,p_settlement_month);
  select coalesce(max(revision_number),0)+1 into v_revision_number from public.settlement_revisions where settlement_id=v_settlement_id;
  insert into public.settlement_revisions(settlement_id,revision_number,normal_minutes,special_minutes,calculated_due_huf,calculation_input_hash,calculated_by,pricing_breakdown)
  values(v_settlement_id,v_revision_number,v_calc.normal_minutes,v_calc.special_minutes,v_calc.calculated_due_huf,v_calc.calculation_input_hash,v_actor,v_calc.pricing_breakdown)
  returning id into v_revision_id;
  for v_line in select * from jsonb_array_elements(v_calc.pricing_breakdown)
  loop
    v_source:=(v_line->>'rate_source')::public.applied_rate_source;
    v_rule_id:=nullif(v_line->>'pricing_rule_id','')::uuid; v_rate:=(v_line->>'hourly_rate_huf')::bigint; v_amount:=(v_line->>'amount_huf')::bigint;
    v_mode:=case v_source when 'central_tier' then 'tiered'::public.pricing_mode when 'training_room' then 'special_room'::public.pricing_mode else 'fixed_user'::public.pricing_mode end;
    insert into public.settlement_booking_lines(
      settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,
      hourly_rate_huf,amount_huf,rate_source,booking_start_at,booking_end_at,room_id,room_name
    ) values(
      v_revision_id,(v_line->>'booking_id')::uuid,(v_line->>'duration_minutes')::integer,
      v_mode,v_rule_id,v_rate,v_amount,v_source,
      (v_line->>'booking_start_at')::timestamptz,(v_line->>'booking_end_at')::timestamptz,
      (v_line->>'room_id')::uuid,v_line->>'room_name'
    );
  end loop;
  select coalesce(sum(amount_huf),0),coalesce(sum(duration_minutes),0)::integer into v_line_total,v_line_minutes from public.settlement_booking_lines where settlement_revision_id=v_revision_id;
  if v_line_total<>v_calc.calculated_due_huf or v_line_minutes<>v_calc.normal_minutes+v_calc.special_minutes then raise exception 'A settlement snapshot ellenőrzése sikertelen.' using errcode='P0001'; end if;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,reason,correlation_id)
  values(v_actor,'monthly_settlement.revision_created','monthly_settlement',v_settlement_id::text,jsonb_build_object('user_id',p_user_id,'settlement_month',p_settlement_month,'revision_id',v_revision_id,'revision_number',v_revision_number,'calculated_due_huf',v_calc.calculated_due_huf,'calculation_input_hash',v_calc.calculation_input_hash),btrim(p_reason),p_correlation_id);
  return query select v_settlement_id,v_revision_id,v_revision_number,v_calc.calculated_due_huf;
end;
$$;

create or replace function public.admin_monthly_pricing_summary(p_month date)
returns table(
  user_id uuid,user_name text,email text,booking_count bigint,total_minutes bigint,total_hours numeric,
  normal_minutes integer,special_minutes integer,calculated_due_huf bigint,
  pricing_state text,revision_id uuid,revision_number integer
)
language plpgsql stable security definer set search_path=''
as $$
declare
  v_month date;
  v_profile record;
  v_revision record;
  v_calc record;
begin
  perform public.require_active_admin();
  if p_month is null then raise exception 'Az elszámolási hónap kötelező.' using errcode='22004'; end if;
  v_month:=date_trunc('month',p_month)::date;
  for v_profile in
    select profile.id,profile.last_name||' '||profile.first_name as name,profile.email
    from public.profiles profile
    where exists(select 1 from public.bookings booking where booking.user_id=profile.id and booking.status='active'
      and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
      and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date)
    order by profile.last_name,profile.first_name,profile.id
  loop
    select revision.id,revision.revision_number,revision.normal_minutes,revision.special_minutes,revision.calculated_due_huf
    into v_revision
    from public.monthly_settlements settlement
    join public.settlement_revisions revision on revision.settlement_id=settlement.id
    where settlement.user_id=v_profile.id and settlement.settlement_month=v_month
    order by revision.revision_number desc limit 1;
    if found then
      return query select v_profile.id,v_profile.name,v_profile.email,count(line.id),
        coalesce(sum(line.duration_minutes),0)::bigint,
        round(coalesce(sum(line.duration_minutes),0)::numeric/60,2),
        v_revision.normal_minutes,v_revision.special_minutes,v_revision.calculated_due_huf,
        'snapshot'::text,v_revision.id,v_revision.revision_number
      from public.settlement_booking_lines line where line.settlement_revision_id=v_revision.id;
    else
      select * into v_calc from public.calculate_monthly_pricing(v_profile.id,v_month);
      return query select v_profile.id,v_profile.name,v_profile.email,count(booking.id),
        coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/60),0)::bigint,
        round(coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/3600),0),2),
        v_calc.normal_minutes,v_calc.special_minutes,v_calc.calculated_due_huf,
        'live'::text,null::uuid,null::integer
      from public.bookings booking where booking.user_id=v_profile.id and booking.status='active'
        and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
        and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date;
    end if;
  end loop;
end;
$$;

create or replace function public.admin_monthly_pricing_details(p_month date,p_user_id uuid default null)
returns table(
  booking_id uuid,user_id uuid,user_name text,booking_date date,room_name text,
  start_time time,end_time time,total_minutes bigint,total_hours numeric,
  rate_source public.applied_rate_source,hourly_rate_huf bigint,amount_huf bigint,
  pricing_state text,revision_number integer
)
language plpgsql stable security definer set search_path=''
as $$
declare v_month date;
begin
  perform public.require_active_admin();
  if p_month is null then raise exception 'Az elszámolási hónap kötelező.' using errcode='22004'; end if;
  v_month:=date_trunc('month',p_month)::date;
  return query
  with latest as (
    select distinct on (settlement.user_id)
      settlement.user_id,revision.id as revision_id,revision.revision_number
    from public.monthly_settlements settlement
    join public.settlement_revisions revision on revision.settlement_id=settlement.id
    where settlement.settlement_month=v_month and (p_user_id is null or settlement.user_id=p_user_id)
    order by settlement.user_id,revision.revision_number desc
  ), result as (
    select line.booking_id,profile.id as user_id,profile.last_name||' '||profile.first_name as user_name,
      (line.booking_start_at at time zone 'Europe/Budapest')::date as booking_date,line.room_name,
      (line.booking_start_at at time zone 'Europe/Budapest')::time as start_time,
      (line.booking_end_at at time zone 'Europe/Budapest')::time as end_time,
      line.duration_minutes::bigint as total_minutes,round(line.duration_minutes::numeric/60,2) as total_hours,
      line.rate_source,line.hourly_rate_huf,line.amount_huf,'snapshot'::text as pricing_state,latest.revision_number
    from latest
    join public.profiles profile on profile.id=latest.user_id
    join public.settlement_booking_lines line on line.settlement_revision_id=latest.revision_id
    union all
    select booking.id,profile.id,profile.last_name||' '||profile.first_name,
      (booking.start_at at time zone 'Europe/Budapest')::date,room.name,
      (booking.start_at at time zone 'Europe/Budapest')::time,
      (booking.end_at at time zone 'Europe/Budapest')::time,
      (extract(epoch from (booking.end_at-booking.start_at))/60)::bigint,
      round(extract(epoch from (booking.end_at-booking.start_at))/3600,2),
      rate.rate_source,rate.hourly_rate_huf,
      round(extract(epoch from (booking.end_at-booking.start_at))/60*rate.hourly_rate_huf/60)::bigint,
      'live'::text,null::integer
    from public.bookings booking
    join public.profiles profile on profile.id=booking.user_id
    join public.rooms room on room.id=booking.room_id
    cross join lateral public.resolve_booking_applied_rate(
      booking.id,public.month_normal_minutes(booking.user_id,v_month)
    ) rate
    where booking.status='active' and (p_user_id is null or booking.user_id=p_user_id)
      and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
      and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date
      and not exists(select 1 from latest where latest.user_id=booking.user_id)
  )
  select result.* from result order by result.user_name,result.booking_date,result.start_time,result.booking_id;
end;
$$;

create or replace function public.admin_correct_historical_booking_rate(
  p_booking_id uuid,p_hourly_rate_huf bigint,p_reason text,p_correlation_id uuid
)
returns table(settlement_id uuid,revision_id uuid,revision_number integer,calculated_due_huf bigint)
language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid:=public.require_active_admin();
  v_booking public.bookings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_month date;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if p_hourly_rate_huf is not null and p_hourly_rate_huf<0 then raise exception 'Az óradíj nem lehet negatív.' using errcode='22023'; end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'A történeti díjkorrekció indoka kötelező.' using errcode='22004'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.status<>'active' then raise exception 'Csak aktív foglalás díja korrigálható.' using errcode='P0001'; end if;
  if v_booking.end_at>now() then raise exception 'Ezt a műveletet csak befejeződött foglaláshoz használd.' using errcode='22023'; end if;
  if v_booking.hourly_rate_override_huf is not distinct from p_hourly_rate_huf then raise exception 'A korrigált óradíj nem változott.' using errcode='22023'; end if;
  v_month:=date_trunc('month',(v_booking.start_at at time zone 'Europe/Budapest')::date)::date;
  if v_month>=date_trunc('month',timezone('Europe/Budapest',now()))::date then
    raise exception 'Csak már befejeződött hónap díja korrigálható.' using errcode='22023';
  end if;
  v_before:=jsonb_build_object('hourly_rate_override_huf',v_booking.hourly_rate_override_huf,'set_by',v_booking.hourly_rate_override_set_by,'set_at',v_booking.hourly_rate_override_set_at,'reason',v_booking.hourly_rate_override_reason);
  update public.bookings set
    hourly_rate_override_huf=p_hourly_rate_huf,
    hourly_rate_override_set_by=case when p_hourly_rate_huf is null then null else v_actor end,
    hourly_rate_override_set_at=case when p_hourly_rate_huf is null then null else clock_timestamp() end,
    hourly_rate_override_reason=case when p_hourly_rate_huf is null then null else btrim(p_reason) end,
    updated_at=clock_timestamp()
  where id=p_booking_id;
  select jsonb_build_object('hourly_rate_override_huf',booking.hourly_rate_override_huf,'set_by',booking.hourly_rate_override_set_by,'set_at',booking.hourly_rate_override_set_at,'reason',booking.hourly_rate_override_reason)
  into v_after from public.bookings booking where booking.id=p_booking_id;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'pricing.booking_historical_rate_corrected','booking',p_booking_id::text,v_before,v_after,btrim(p_reason),p_correlation_id);
  return query select * from public.admin_create_monthly_settlement_revision(v_booking.user_id,v_month,p_reason,p_correlation_id);
end;
$$;

revoke all on function public.month_normal_minutes(uuid,date,uuid,integer,boolean) from public,anon,authenticated,service_role;
revoke all on function public.resolve_booking_applied_rate(uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.calculate_monthly_pricing(uuid,date) from public,anon,authenticated,service_role;
revoke all on function public.prevent_settlement_snapshot_mutation() from public,anon,authenticated,service_role;
revoke all on function public.claim_admin_pricing_request(uuid,text,bigint,text) from public,anon,authenticated,service_role;

revoke all on function public.admin_calculate_monthly_pricing(uuid,date) from public,anon;
revoke all on function public.admin_pricing_quote(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,uuid,bigint) from public,anon;
revoke all on function public.admin_list_pricing_rules() from public,anon;
revoke all on function public.admin_list_user_price_overrides(uuid) from public,anon;
revoke all on function public.admin_set_central_pricing(date,bigint,bigint,bigint,text,uuid) from public,anon;
revoke all on function public.admin_set_training_room_rate(bigint,date,text,uuid) from public,anon;
revoke all on function public.admin_set_user_hourly_rate(uuid,bigint,date,text,uuid) from public,anon;
revoke all on function public.admin_set_booking_hourly_rate_override(uuid,bigint,text,uuid) from public,anon;
revoke all on function public.admin_create_booking_with_pricing(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint,text) from public,anon;
revoke all on function public.admin_update_booking_with_pricing(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint,text) from public,anon;
revoke all on function public.admin_update_booking_scope_with_pricing(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,boolean,bigint,text) from public,anon;
revoke all on function public.admin_create_booking_series_with_pricing(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text,bigint,text) from public,anon;
revoke all on function public.admin_create_monthly_settlement_revision(uuid,date,text,uuid) from public,anon;
revoke all on function public.admin_monthly_pricing_summary(date) from public,anon;
revoke all on function public.admin_monthly_pricing_details(date,uuid) from public,anon;
revoke all on function public.admin_correct_historical_booking_rate(uuid,bigint,text,uuid) from public,anon;
revoke all on function public.list_calendar_booking_management(timestamptz,timestamptz) from public,anon;

grant execute on function public.admin_calculate_monthly_pricing(uuid,date) to authenticated,service_role;
grant execute on function public.admin_pricing_quote(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,uuid,bigint) to authenticated,service_role;
grant execute on function public.admin_list_pricing_rules() to authenticated,service_role;
grant execute on function public.admin_list_user_price_overrides(uuid) to authenticated,service_role;
grant execute on function public.admin_set_central_pricing(date,bigint,bigint,bigint,text,uuid) to authenticated,service_role;
grant execute on function public.admin_set_training_room_rate(bigint,date,text,uuid) to authenticated,service_role;
grant execute on function public.admin_set_user_hourly_rate(uuid,bigint,date,text,uuid) to authenticated,service_role;
grant execute on function public.admin_set_booking_hourly_rate_override(uuid,bigint,text,uuid) to authenticated,service_role;
grant execute on function public.admin_create_booking_with_pricing(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint,text) to authenticated,service_role;
grant execute on function public.admin_update_booking_with_pricing(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint,text) to authenticated,service_role;
grant execute on function public.admin_update_booking_scope_with_pricing(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,boolean,bigint,text) to authenticated,service_role;
grant execute on function public.admin_create_booking_series_with_pricing(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text,bigint,text) to authenticated,service_role;
grant execute on function public.admin_create_monthly_settlement_revision(uuid,date,text,uuid) to authenticated,service_role;
grant execute on function public.admin_monthly_pricing_summary(date) to authenticated,service_role;
grant execute on function public.admin_monthly_pricing_details(date,uuid) to authenticated,service_role;
grant execute on function public.admin_correct_historical_booking_rate(uuid,bigint,text,uuid) to authenticated,service_role;
grant execute on function public.list_calendar_booking_management(timestamptz,timestamptz) to authenticated,service_role;

comment on column public.bookings.hourly_rate_override_huf is 'Admin-only per-booking hourly-rate override. NULL means automatic pricing.';
comment on function public.calculate_monthly_pricing(uuid,date) is 'Canonical monthly pricing calculation. Internal only; admin wrapper enforces authorization.';

commit;
