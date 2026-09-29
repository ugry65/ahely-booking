begin;

-- One row per month is the authoritative period-level publication marker. The
-- financial values remain in monthly_settlements/settlement_revisions; this
-- table records only the atomic close and its audit summary.
create table public.monthly_settlement_periods (
  settlement_month date primary key,
  closed_at timestamptz not null,
  closed_by uuid not null references public.profiles(id) on delete restrict,
  participant_count integer not null check (participant_count >= 0),
  total_minutes bigint not null check (total_minutes >= 0),
  total_due_huf bigint not null check (total_due_huf >= 0),
  snapshot_hash text not null,
  correlation_id uuid not null,
  constraint monthly_settlement_period_month_start
    check (settlement_month = date_trunc('month', settlement_month)::date)
);

alter table public.monthly_settlement_periods enable row level security;
revoke all on table public.monthly_settlement_periods from public, anon, authenticated;
revoke all on table public.monthly_settlements from public, anon, authenticated;
revoke all on table public.settlement_revisions from public, anon, authenticated;
revoke all on table public.settlement_booking_lines from public, anon, authenticated;

create or replace function public.prevent_monthly_settlement_period_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'A hónaplezárási esemény nem módosítható vagy törölhető.'
    using errcode = '42501';
end;
$$;

create trigger monthly_settlement_periods_immutable
before update or delete on public.monthly_settlement_periods
for each row execute function public.prevent_monthly_settlement_period_mutation();
revoke all on function public.prevent_monthly_settlement_period_mutation() from public, anon, authenticated, service_role;

create or replace function public.prevent_closed_settlement_revision_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.monthly_settlements ms
    where ms.id = new.settlement_id and ms.is_closed
  ) and not public.is_admin() then
    raise exception 'Lezárt havi elszámolás új revisionjét csak adminisztrátor készítheti.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_closed_settlement_metadata_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_revision public.settlement_revisions%rowtype;
begin
  if old.is_closed and (
    new.is_closed is distinct from old.is_closed
    or new.closed_at is distinct from old.closed_at
    or new.closed_by is distinct from old.closed_by
  ) then
    raise exception 'A lezárt havi elszámolás lezárási adatai nem módosíthatók.'
      using errcode = '42501';
  end if;

  if old.is_closed and new.closed_revision_id is distinct from old.closed_revision_id then
    if not public.is_admin() or new.closed_revision_id is null then
      raise exception 'A lezárt elszámolás revisionjét csak auditált admin korrekció válthatja.'
        using errcode = '42501';
    end if;
    select * into v_revision
    from public.settlement_revisions sr
    where sr.id = new.closed_revision_id and sr.settlement_id = old.id;
    if not found or v_revision.revision_number <= (
      select old_revision.revision_number
      from public.settlement_revisions old_revision
      where old_revision.id = old.closed_revision_id
    ) then
      raise exception 'Csak ugyanahhoz az elszámoláshoz tartozó újabb revision aktiválható.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- Serialize every settlement-affecting booking write with the period close.
-- Normal users are denied after publication; admins may make an explicit
-- correction and then publish a new immutable revision through the admin UI.
create or replace function public.guard_published_settlement_booking_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_role public.app_role;
  v_months date[];
  v_month date;
begin
  if tg_op = 'DELETE' then
    v_months := array[date_trunc('month', (old.start_at at time zone 'Europe/Budapest')::date)::date];
  elsif tg_op = 'INSERT' then
    if new.status <> 'active' then return new; end if;
    v_months := array[date_trunc('month', (new.start_at at time zone 'Europe/Budapest')::date)::date];
  else
    if old.status <> 'active' and new.status <> 'active' then return new; end if;
    v_months := array[
      date_trunc('month', (old.start_at at time zone 'Europe/Budapest')::date)::date,
      date_trunc('month', (new.start_at at time zone 'Europe/Budapest')::date)::date
    ];
  end if;

  -- Auth-less service operations remain trusted/internal. Every public RPC
  -- retains its own authorization checks.
  if v_actor is null then
    foreach v_month in array v_months loop
      perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('monthly-settlement-period:' || v_month::text, 0)
      );
    end loop;
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  select p.role into v_role from public.profiles p
  where p.id = v_actor and p.is_active;
  if v_role is null then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  for v_month in
    select distinct month_value from unnest(v_months) as months(month_value) order by month_value
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('monthly-settlement-period:' || v_month::text, 0)
    );
  end loop;

  if exists (
    select 1 from public.monthly_settlement_periods period
    where period.settlement_month = any(v_months)
  ) and (
    v_role <> 'admin'
    or tg_op = 'DELETE'
    or coalesce(current_setting('ahely.internal_settlement_correction', true), '') <> 'on'
       and not (tg_op = 'UPDATE' and old.status = 'active' and new.status = 'cancelled'
         and old.user_id = new.user_id and old.room_id = new.room_id
         and old.start_at = new.start_at and old.end_at = new.end_at and old.use_type = new.use_type
         and old.hourly_rate_override_huf is not distinct from new.hourly_rate_override_huf)
  ) then
    raise exception 'A lezárt hónap foglalása csak auditált adminisztrátori korrekcióval módosítható.'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.publish_revision_after_closed_admin_cancellation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_month date;
begin
  v_month := date_trunc('month', ((select b.start_at from public.bookings b where b.id = new.booking_id)
    at time zone 'Europe/Budapest')::date)::date;
  if exists (select 1 from public.monthly_settlement_periods p where p.settlement_month = v_month) then
    if not public.is_admin() or auth.uid() is distinct from new.cancelled_by then
      raise exception 'Lezárt hónapban csak adminisztrátor készíthet elszámolási korrekciót.' using errcode = '42501';
    end if;
    if nullif(btrim(new.reason), '') is null then
      raise exception 'Lezárt hónap foglalásának adminisztrátori lemondásához korrekciós indok szükséges.' using errcode = '22004';
    end if;
    perform public.admin_create_monthly_settlement_revision(
      (select b.user_id from public.bookings b where b.id = new.booking_id),
      v_month,
      'Admin lemondás utáni havi elszámolási korrekció: ' || btrim(new.reason),
      extensions.gen_random_uuid()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists booking_cancellations_publish_closed_settlement_revision on public.booking_cancellations;
create trigger booking_cancellations_publish_closed_settlement_revision
after insert on public.booking_cancellations
for each row execute function public.publish_revision_after_closed_admin_cancellation();
revoke all on function public.publish_revision_after_closed_admin_cancellation() from public, anon, authenticated, service_role;

drop trigger if exists bookings_guard_published_settlement_write on public.bookings;
create trigger bookings_guard_published_settlement_write
before insert or delete or update of user_id, room_id, start_at, end_at, use_type,
  status, hourly_rate_override_huf
on public.bookings
for each row execute function public.guard_published_settlement_booking_write();
revoke all on function public.guard_published_settlement_booking_write() from public, anon, authenticated, service_role;

create or replace function public.monthly_settlement_cutoff_blockers(
  p_month date,
  p_as_of timestamptz
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cutoff_hours integer;
  v_count bigint;
begin
  select (value #>> '{}')::integer into v_cutoff_hours
  from public.app_settings where key = 'cancellation_cutoff_hours';
  if v_cutoff_hours is null or v_cutoff_hours < 0 then
    raise exception 'A foglalási módosítási határidő beállítása hiányzik vagy érvénytelen.' using errcode = 'P0001';
  end if;
  if p_month is null or p_as_of is null then
    raise exception 'A hónap és az időpont kötelező.' using errcode = '22004';
  end if;
  select count(*)::bigint into v_count
  from public.bookings b
  where b.status = 'active'
    and (b.start_at at time zone 'Europe/Budapest')::date >= p_month
    and (b.start_at at time zone 'Europe/Budapest')::date < (p_month + interval '1 month')::date
    -- Equality is still mutable under the existing 24h rule.
    and b.start_at >= p_as_of + make_interval(hours => v_cutoff_hours);
  return v_count;
end;
$$;

revoke all on function public.monthly_settlement_cutoff_blockers(date,timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.admin_monthly_settlement_close_preview(p_month date)
returns table (
  settlement_month date,
  can_close boolean,
  already_closed boolean,
  blocked_booking_count bigint,
  participant_count integer,
  total_minutes bigint,
  total_due_huf bigint,
  closed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date;
  v_now timestamptz := clock_timestamp();
  v_current_month date := date_trunc('month', timezone('Europe/Budapest', clock_timestamp()))::date;
  v_blocked bigint;
begin
  perform public.require_active_admin();
  if p_month is null then
    raise exception 'Az elszámolási hónap kötelező.' using errcode = '22004';
  end if;
  v_month := date_trunc('month', p_month)::date;
  v_blocked := public.monthly_settlement_cutoff_blockers(v_month, v_now);
  return query
  with eligible_profiles as (
    select p.id from public.profiles p
    where exists (
      select 1 from public.bookings b
      where b.user_id = p.id and b.status = 'active'
        and (b.start_at at time zone 'Europe/Budapest')::date >= v_month
        and (b.start_at at time zone 'Europe/Budapest')::date < (v_month + interval '1 month')::date
    ) or exists (
      select 1 from public.monthly_settlements ms
      where ms.user_id = p.id and ms.settlement_month = v_month
    )
  ), live_totals as (
    select count(*)::integer as users,
      coalesce(sum(calc.normal_minutes + calc.special_minutes), 0)::bigint as minutes,
      coalesce(sum(calc.calculated_due_huf), 0)::bigint as due
    from eligible_profiles ep
    cross join lateral public.calculate_monthly_pricing(ep.id, v_month) calc
  ), closed as (
    select period.closed_at from public.monthly_settlement_periods period
    where period.settlement_month = v_month
  )
  select v_month,
    v_month <= v_current_month and v_blocked = 0 and not exists(select 1 from closed),
    exists(select 1 from closed),
    v_blocked,
    live_totals.users,
    live_totals.minutes,
    live_totals.due,
    (select c.closed_at from closed c)
  from live_totals;
end;
$$;

revoke all on function public.admin_monthly_settlement_close_preview(date) from public, anon;
grant execute on function public.admin_monthly_settlement_close_preview(date) to authenticated;

create or replace function public.admin_create_monthly_settlement_revision(
  p_user_id uuid,
  p_settlement_month date,
  p_reason text,
  p_correlation_id uuid
)
returns table(settlement_id uuid, revision_id uuid, revision_number integer, calculated_due_huf bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_month date;
  v_settlement_id uuid;
  v_is_closed boolean;
  v_revision_id uuid;
  v_revision_number integer;
  v_calc record;
  v_line jsonb;
  v_source public.applied_rate_source;
  v_mode public.pricing_mode;
  v_rule_id uuid;
  v_rate bigint;
  v_amount bigint;
  v_line_total bigint;
  v_line_minutes integer;
begin
  if p_user_id is null or p_correlation_id is null then
    raise exception 'A felhasználó és korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Az elszámolási revision indoka kötelező.' using errcode = '22004';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;
  v_month := p_settlement_month;
  if v_month >= date_trunc('month', timezone('Europe/Budapest', now()))::date
     and not exists(select 1 from public.monthly_settlement_periods p where p.settlement_month = v_month)
     and coalesce(current_setting('ahely.internal_month_close', true), '') <> 'on' then
    raise exception 'Csak befejeződött vagy már lezárt hónapról készíthető végleges revision.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':' || v_month::text, 0)
  );
  insert into public.monthly_settlements(user_id, settlement_month)
  values (p_user_id, v_month)
  on conflict(user_id, settlement_month) do update set updated_at = now()
  returning id, is_closed into v_settlement_id, v_is_closed;

  select * into v_calc from public.calculate_monthly_pricing(p_user_id, v_month);
  select coalesce(max(sr.revision_number), 0) + 1 into v_revision_number
  from public.settlement_revisions sr where sr.settlement_id = v_settlement_id;

  insert into public.settlement_revisions(
    settlement_id, revision_number, normal_minutes, special_minutes,
    calculated_due_huf, calculation_input_hash, calculated_by, pricing_breakdown
  ) values (
    v_settlement_id, v_revision_number, v_calc.normal_minutes, v_calc.special_minutes,
    v_calc.calculated_due_huf, v_calc.calculation_input_hash, v_actor, v_calc.pricing_breakdown
  ) returning id into v_revision_id;

  for v_line in select * from jsonb_array_elements(coalesce(v_calc.pricing_breakdown, '[]'::jsonb)) loop
    v_source := (v_line->>'rate_source')::public.applied_rate_source;
    v_rule_id := nullif(v_line->>'pricing_rule_id', '')::uuid;
    v_rate := (v_line->>'hourly_rate_huf')::bigint;
    v_amount := (v_line->>'amount_huf')::bigint;
    v_mode := case v_source
      when 'central_tier' then 'tiered'::public.pricing_mode
      when 'training_room' then 'special_room'::public.pricing_mode
      else 'fixed_user'::public.pricing_mode end;
    insert into public.settlement_booking_lines(
      settlement_revision_id, booking_id, duration_minutes, pricing_mode,
      pricing_rule_id, hourly_rate_huf, amount_huf, rate_source,
      booking_start_at, booking_end_at, room_id, room_name
    ) values (
      v_revision_id, (v_line->>'booking_id')::uuid,
      (v_line->>'duration_minutes')::integer, v_mode, v_rule_id, v_rate, v_amount,
      v_source, (v_line->>'booking_start_at')::timestamptz,
      (v_line->>'booking_end_at')::timestamptz, (v_line->>'room_id')::uuid,
      v_line->>'room_name'
    );
  end loop;

  select coalesce(sum(line.amount_huf), 0), coalesce(sum(line.duration_minutes), 0)::integer
  into v_line_total, v_line_minutes
  from public.settlement_booking_lines line where line.settlement_revision_id = v_revision_id;
  if v_line_total <> v_calc.calculated_due_huf
     or v_line_minutes <> v_calc.normal_minutes + v_calc.special_minutes then
    raise exception 'A settlement snapshot ellenőrzése sikertelen.' using errcode = 'P0001';
  end if;

  if v_is_closed then
    update public.monthly_settlements
    set closed_revision_id = v_revision_id, updated_at = clock_timestamp()
    where id = v_settlement_id;
  end if;

  insert into public.audit_logs(
    actor_user_id, action, entity_type, entity_id, after_data, reason, correlation_id
  ) values (
    v_actor, case when v_is_closed then 'monthly_settlement.corrected' else 'monthly_settlement.revision_created' end,
    'monthly_settlement', v_settlement_id::text,
    jsonb_build_object('user_id', p_user_id, 'settlement_month', v_month,
      'revision_id', v_revision_id, 'revision_number', v_revision_number,
      'calculated_due_huf', v_calc.calculated_due_huf,
      'normal_minutes', v_calc.normal_minutes, 'special_minutes', v_calc.special_minutes,
      'calculation_input_hash', v_calc.calculation_input_hash),
    btrim(p_reason), p_correlation_id
  );
  return query select v_settlement_id, v_revision_id, v_revision_number, v_calc.calculated_due_huf;
end;
$$;

revoke all on function public.admin_create_monthly_settlement_revision(uuid,date,text,uuid) from public, anon;
grant execute on function public.admin_create_monthly_settlement_revision(uuid,date,text,uuid) to authenticated, service_role;

create or replace function public.admin_correct_historical_booking_rate(
  p_booking_id uuid, p_hourly_rate_huf bigint, p_reason text, p_correlation_id uuid
)
returns table(settlement_id uuid, revision_id uuid, revision_number integer, calculated_due_huf bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_booking public.bookings%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_month date;
begin
  if p_correlation_id is null or nullif(btrim(p_reason), '') is null then
    raise exception 'A korrekció indoka és korrelációs azonosítója kötelező.' using errcode = '22004';
  end if;
  if p_hourly_rate_huf is not null and p_hourly_rate_huf < 0 then
    raise exception 'Az óradíj nem lehet negatív.' using errcode = '22023';
  end if;
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found or v_booking.status <> 'active' then
    raise exception 'Csak aktív foglalás díja korrigálható.' using errcode = 'P0001';
  end if;
  if v_booking.end_at > clock_timestamp() then
    raise exception 'Ezt a műveletet csak befejeződött foglaláshoz használd.' using errcode = '22023';
  end if;
  if v_booking.hourly_rate_override_huf is not distinct from p_hourly_rate_huf then
    raise exception 'A korrigált óradíj nem változott.' using errcode = '22023';
  end if;
  v_month := date_trunc('month', (v_booking.start_at at time zone 'Europe/Budapest')::date)::date;
  if v_month >= date_trunc('month', timezone('Europe/Budapest', clock_timestamp()))::date
     and not exists (select 1 from public.monthly_settlement_periods p where p.settlement_month = v_month) then
    raise exception 'Csak már lezárt hónap díja korrigálható.' using errcode = '22023';
  end if;
  v_before := jsonb_build_object('hourly_rate_override_huf', v_booking.hourly_rate_override_huf,
    'set_by', v_booking.hourly_rate_override_set_by, 'set_at', v_booking.hourly_rate_override_set_at,
    'reason', v_booking.hourly_rate_override_reason);
  perform set_config('ahely.internal_settlement_correction', 'on', true);
  update public.bookings set
    hourly_rate_override_huf = p_hourly_rate_huf,
    hourly_rate_override_set_by = case when p_hourly_rate_huf is null then null else v_actor end,
    hourly_rate_override_set_at = case when p_hourly_rate_huf is null then null else clock_timestamp() end,
    hourly_rate_override_reason = case when p_hourly_rate_huf is null then null else btrim(p_reason) end,
    updated_at = clock_timestamp()
  where id = p_booking_id;
  select jsonb_build_object('hourly_rate_override_huf', b.hourly_rate_override_huf,
    'set_by', b.hourly_rate_override_set_by, 'set_at', b.hourly_rate_override_set_at,
    'reason', b.hourly_rate_override_reason) into v_after
  from public.bookings b where b.id = p_booking_id;
  insert into public.audit_logs(actor_user_id, action, entity_type, entity_id,
    before_data, after_data, reason, correlation_id)
  values (v_actor, 'pricing.booking_historical_rate_corrected', 'booking', p_booking_id::text,
    v_before, v_after, btrim(p_reason), p_correlation_id);
  return query select * from public.admin_create_monthly_settlement_revision(
    v_booking.user_id, v_month, p_reason, p_correlation_id
  );
end;
$$;

revoke all on function public.admin_correct_historical_booking_rate(uuid,bigint,text,uuid) from public, anon;
grant execute on function public.admin_correct_historical_booking_rate(uuid,bigint,text,uuid) to authenticated, service_role;

create or replace function public.admin_close_monthly_settlement_period(p_month date)
returns table (
  settlement_month date,
  participant_count integer,
  total_minutes bigint,
  total_due_huf bigint,
  closed_at timestamptz,
  snapshot_hash text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_month date;
  v_now timestamptz := clock_timestamp();
  v_current_month date := date_trunc('month', timezone('Europe/Budapest', clock_timestamp()))::date;
  v_correlation uuid := extensions.gen_random_uuid();
  v_blocked bigint;
  v_participants integer;
  v_minutes bigint;
  v_due bigint;
  v_hash text;
  v_user record;
  v_revision record;
  v_closed_at timestamptz;
begin
  if p_month is null or p_month <> date_trunc('month', p_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;
  v_month := p_month;
  if v_month > v_current_month then
    raise exception 'Jövőbeli hónap nem zárható le.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('monthly-settlement-period:' || v_month::text, 0)
  );
  if exists(select 1 from public.monthly_settlement_periods p where p.settlement_month = v_month) then
    raise exception 'Ez a hónap már le van zárva.' using errcode = 'P0001';
  end if;

  v_blocked := public.monthly_settlement_cutoff_blockers(v_month, v_now);
  if v_blocked > 0 then
    raise exception 'A hónap még nem zárható le: % aktív foglalás normál felhasználóként még módosítható vagy lemondható.', v_blocked
      using errcode = 'P0001';
  end if;

  -- Internal, transaction-scoped authorization for the initial same-month
  -- snapshot. The only public entry point still requires an active admin.
  perform set_config('ahely.internal_month_close', 'on', true);

  for v_user in
    select p.id from public.profiles p
    where exists (
      select 1 from public.bookings b
      where b.user_id = p.id and b.status = 'active'
        and (b.start_at at time zone 'Europe/Budapest')::date >= v_month
        and (b.start_at at time zone 'Europe/Budapest')::date < (v_month + interval '1 month')::date
    ) or exists (
      select 1 from public.monthly_settlements ms
      where ms.user_id = p.id and ms.settlement_month = v_month
    )
    order by p.id
  loop
    select * into v_revision
    from public.admin_create_monthly_settlement_revision(
      v_user.id, v_month, 'Havi elszámolás első publikálása', v_correlation
    );
    update public.monthly_settlements ms
    set is_closed = true, closed_at = v_now, closed_by = v_actor,
        closed_revision_id = v_revision.revision_id, updated_at = v_now
    where ms.id = v_revision.settlement_id and not ms.is_closed;
    if not found and not exists (
      select 1 from public.monthly_settlements ms
      where ms.id = v_revision.settlement_id and ms.is_closed
        and ms.closed_revision_id = v_revision.revision_id
    ) then
      raise exception 'A user havi elszámolásának lezárása nem sikerült.' using errcode = 'P0001';
    end if;
  end loop;

  select count(*)::integer,
    coalesce(sum(revision.normal_minutes + revision.special_minutes), 0)::bigint,
    coalesce(sum(revision.calculated_due_huf), 0)::bigint,
    encode(extensions.digest(coalesce(string_agg(
      settlement.user_id::text || ':' || revision.id::text || ':' || revision.calculation_input_hash,
      '|' order by settlement.user_id
    ), ''), 'sha256'), 'hex')
  into v_participants, v_minutes, v_due, v_hash
  from public.monthly_settlements settlement
  join public.settlement_revisions revision on revision.id = settlement.closed_revision_id
  where settlement.settlement_month = v_month and settlement.is_closed;

  insert into public.monthly_settlement_periods(
    settlement_month, closed_at, closed_by, participant_count,
    total_minutes, total_due_huf, snapshot_hash, correlation_id
  ) values (
    v_month, v_now, v_actor, v_participants, v_minutes, v_due, v_hash, v_correlation
  );

  insert into public.audit_logs(
    actor_user_id, action, entity_type, entity_id, after_data, reason, correlation_id
  ) values (
    v_actor, 'monthly_settlement.period_closed', 'monthly_settlement_period', v_month::text,
    jsonb_build_object('settlement_month', v_month, 'closed_at', v_now,
      'participant_count', v_participants, 'total_minutes', v_minutes,
      'total_due_huf', v_due, 'snapshot_hash', v_hash,
      'revisions', coalesce((
        select jsonb_agg(jsonb_build_object('user_id', settlement.user_id,
          'revision_id', settlement.closed_revision_id)
          order by settlement.user_id)
        from public.monthly_settlements settlement
        where settlement.settlement_month = v_month and settlement.is_closed
      ), '[]'::jsonb)),
    'Havi elszámolás lezárása és publikálása', v_correlation
  );
  return query select v_month, v_participants, v_minutes, v_due, v_now, v_hash;
end;
$$;

revoke all on function public.admin_close_monthly_settlement_period(date) from public, anon;
grant execute on function public.admin_close_monthly_settlement_period(date) to authenticated;

-- Retire the old per-user close endpoint so a partial month cannot be mistaken
-- for the new atomic period publication.
revoke all on function public.admin_close_monthly_settlement(uuid,date) from public, anon, authenticated, service_role;

create or replace function public.list_my_latest_closed_monthly_settlement()
returns table (
  settlement_month date,
  total_minutes integer,
  calculated_due_huf bigint,
  closed_at timestamptz,
  revision_id uuid,
  revision_number integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not exists (
    select 1 from public.profiles p where p.id = v_actor and p.is_active
  ) then
    raise exception 'Aktív bejelentkezés szükséges.' using errcode = '42501';
  end if;
  return query
  select ms.settlement_month, sr.normal_minutes + sr.special_minutes,
    sr.calculated_due_huf, period.closed_at, sr.id, sr.revision_number
  from public.monthly_settlements ms
  join public.monthly_settlement_periods period on period.settlement_month = ms.settlement_month
  join public.settlement_revisions sr on sr.id = ms.closed_revision_id
  where ms.user_id = v_actor and ms.is_closed
  order by ms.settlement_month desc
  limit 1;
end;
$$;

revoke all on function public.list_my_latest_closed_monthly_settlement() from public, anon;
grant execute on function public.list_my_latest_closed_monthly_settlement() to authenticated;

comment on table public.monthly_settlement_periods is
  'Immutable, month-wide publication event. Monetary values remain in existing settlement revisions.';
comment on function public.admin_close_monthly_settlement_period(date) is
  'Atomically snapshots and publishes every user/month settlement after existing normal-user mutation cutoffs have elapsed.';
comment on function public.list_my_latest_closed_monthly_settlement() is
  'Returns only the authenticated user’s latest published monthly settlement; no user id parameter is accepted.';

commit;
