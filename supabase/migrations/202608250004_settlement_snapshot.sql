begin;

alter table public.monthly_settlements
  add column is_closed boolean not null default false,
  add column closed_at timestamptz,
  add column closed_by uuid references public.profiles(id) on delete restrict,
  add column closed_revision_id uuid;

alter table public.settlement_revisions
  add column pricing_scheme public.user_pricing_scheme,
  add column pricing_breakdown jsonb not null default '[]'::jsonb;

alter table public.settlement_booking_lines
  drop constraint settlement_booking_line_unique,
  add column line_part_index integer not null default 1 check (line_part_index > 0),
  add column pricing_scheme public.user_pricing_scheme,
  add column line_kind public.monthly_pricing_line_kind not null default 'normal';

alter table public.settlement_booking_lines
  alter column pricing_mode drop not null,
  add constraint settlement_booking_line_part_unique
    unique (settlement_revision_id, booking_id, line_part_index),
  add constraint settlement_booking_line_mode_consistency check (
    (line_kind = 'free' and pricing_mode is null and hourly_rate_huf = 0 and amount_huf = 0)
    or
    (line_kind <> 'free' and pricing_mode is not null)
  );

alter table public.monthly_settlements
  add constraint monthly_settlement_closed_revision_fk
    foreign key (closed_revision_id) references public.settlement_revisions(id) on delete restrict,
  add constraint monthly_settlement_closed_consistency check (
    (not is_closed and closed_at is null and closed_by is null and closed_revision_id is null)
    or
    (is_closed and closed_at is not null and closed_by is not null and closed_revision_id is not null)
  );

create or replace function public.prevent_settlement_snapshot_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'A lezárt elszámolási snapshot nem módosítható.' using errcode = '42501';
end;
$$;

create trigger settlement_revisions_immutable
before update or delete on public.settlement_revisions
for each row execute function public.prevent_settlement_snapshot_mutation();

create trigger settlement_booking_lines_immutable
before update on public.settlement_booking_lines
for each row execute function public.prevent_settlement_snapshot_mutation();

create or replace function public.admin_close_monthly_settlement(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  settlement_id uuid,
  revision_id uuid,
  revision_number integer,
  calculated_due_huf bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_current_month date;
  v_settlement_id uuid;
  v_is_closed boolean;
  v_revision_id uuid;
  v_revision_number integer;
  v_calc record;
  v_booking record;
  v_tier record;
  v_fixed_rate bigint;
  v_special_rule_id uuid;
  v_special_rate bigint;
  v_booking_minutes integer;
  v_remaining integer;
  v_slice integer;
  v_consumed_normal integer := 0;
  v_part integer;
  v_line_total bigint;
  v_line_minutes integer;
  v_correlation_id uuid := extensions.gen_random_uuid();
begin
  perform public.require_active_admin();
  v_actor := auth.uid();

  if p_user_id is null or not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  v_current_month := date_trunc('month', pg_catalog.timezone('Europe/Budapest', now()))::date;
  if p_settlement_month >= v_current_month then
    raise exception 'Csak már befejeződött hónap zárható le.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user_id::text || ':' || p_settlement_month::text, 0)
  );

  insert into public.monthly_settlements (user_id, settlement_month)
  values (p_user_id, p_settlement_month)
  on conflict (user_id, settlement_month) do update
    set updated_at = now()
  returning id, is_closed into v_settlement_id, v_is_closed;

  if v_is_closed then
    raise exception 'Ez a havi elszámolás már le van zárva.' using errcode = 'P0001';
  end if;

  select * into v_calc
  from public.calculate_monthly_pricing(p_user_id, p_settlement_month);

  select coalesce(max(sr.revision_number), 0) + 1
    into v_revision_number
  from public.settlement_revisions sr
  where sr.settlement_id = v_settlement_id;

  insert into public.settlement_revisions (
    settlement_id,
    revision_number,
    normal_minutes,
    special_minutes,
    calculated_due_huf,
    calculation_input_hash,
    calculated_by,
    pricing_scheme,
    pricing_breakdown
  ) values (
    v_settlement_id,
    v_revision_number,
    v_calc.normal_minutes,
    v_calc.special_minutes,
    v_calc.calculated_due_huf,
    v_calc.calculation_input_hash,
    v_actor,
    v_calc.pricing_scheme,
    v_calc.pricing_breakdown
  ) returning id into v_revision_id;

  select override.hourly_rate_huf
    into v_fixed_rate
  from public.user_price_overrides override
  where override.user_id = p_user_id
    and p_settlement_month between override.valid_from and coalesce(override.valid_to, 'infinity'::date)
  order by override.valid_from desc
  limit 1;

  if v_calc.special_minutes > 0 and v_calc.pricing_scheme <> 'free' then
    select rate.id, rate.hourly_rate_huf
      into v_special_rule_id, v_special_rate
    from public.special_room_rates rate
    join public.rooms r on r.id = rate.room_id
    where r.is_training_room
      and rate.use_type = 'group'
      and p_settlement_month between rate.valid_from and coalesce(rate.valid_to, 'infinity'::date)
    order by rate.valid_from desc
    limit 1;
  end if;

  if v_calc.normal_minutes > 0 and v_calc.pricing_scheme = 'tiered' and v_fixed_rate is null then
    select t.id, t.min_minutes, t.max_minutes, t.hourly_rate_huf
      into v_tier
    from public.pricing_tiers t
    where v_calc.normal_minutes between t.min_minutes and coalesce(t.max_minutes, 2147483647)
      and p_settlement_month between t.valid_from and coalesce(t.valid_to, 'infinity'::date)
    order by t.min_minutes desc
    limit 1;
  end if;

  for v_booking in
    select
      b.id,
      b.start_at,
      (extract(epoch from (b.end_at - b.start_at)) / 60)::integer as duration_minutes,
      (r.is_training_room and b.use_type = 'group') as is_special
    from public.bookings b
    join public.rooms r on r.id = b.room_id
    where b.user_id = p_user_id
      and b.status = 'active'
      and (b.start_at at time zone 'Europe/Budapest')::date >= p_settlement_month
      and (b.start_at at time zone 'Europe/Budapest')::date < (p_settlement_month + interval '1 month')::date
    order by b.start_at, b.id
  loop
    v_booking_minutes := v_booking.duration_minutes;

    if v_calc.pricing_scheme = 'free' then
      insert into public.settlement_booking_lines (
        settlement_revision_id, booking_id, duration_minutes, pricing_mode,
        pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
        pricing_scheme, line_kind
      ) values (
        v_revision_id, v_booking.id, v_booking_minutes, null,
        null, 0, 0, 1, 'free', 'free'
      );

    elsif v_booking.is_special then
      if v_special_rule_id is null then
        raise exception 'Nincs érvényes Tréningterem csoportos díj a snapshothoz.' using errcode = 'P0001';
      end if;
      insert into public.settlement_booking_lines (
        settlement_revision_id, booking_id, duration_minutes, pricing_mode,
        pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
        pricing_scheme, line_kind
      ) values (
        v_revision_id, v_booking.id, v_booking_minutes, 'special_room',
        v_special_rule_id, v_special_rate,
        round(v_booking_minutes::numeric * v_special_rate / 60)::bigint,
        1, v_calc.pricing_scheme, 'special_room'
      );

    elsif v_fixed_rate is not null then
      insert into public.settlement_booking_lines (
        settlement_revision_id, booking_id, duration_minutes, pricing_mode,
        pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
        pricing_scheme, line_kind
      ) values (
        v_revision_id, v_booking.id, v_booking_minutes, 'fixed_user',
        null, v_fixed_rate,
        round(v_booking_minutes::numeric * v_fixed_rate / 60)::bigint,
        1, v_calc.pricing_scheme, 'normal'
      );

    elsif v_calc.pricing_scheme = 'tiered' then
      if v_tier.id is null then
        raise exception 'Nincs érvényes díjsáv a snapshothoz.' using errcode = 'P0001';
      end if;
      insert into public.settlement_booking_lines (
        settlement_revision_id, booking_id, duration_minutes, pricing_mode,
        pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
        pricing_scheme, line_kind
      ) values (
        v_revision_id, v_booking.id, v_booking_minutes, 'tiered',
        v_tier.id, v_tier.hourly_rate_huf,
        round(v_booking_minutes::numeric * v_tier.hourly_rate_huf / 60)::bigint,
        1, 'tiered', 'normal'
      );

    else
      v_remaining := v_booking_minutes;
      v_part := 1;
      while v_remaining > 0 loop
        select t.id, t.max_minutes, t.hourly_rate_huf
          into v_tier
        from public.pricing_tiers t
        where p_settlement_month between t.valid_from and coalesce(t.valid_to, 'infinity'::date)
          and (t.max_minutes is null or v_consumed_normal < t.max_minutes)
        order by t.min_minutes
        limit 1;

        if v_tier.id is null then
          raise exception 'A progresszív díjsávok nem fedik le a snapshotot.' using errcode = 'P0001';
        end if;

        if v_tier.max_minutes is null then
          v_slice := v_remaining;
        else
          v_slice := least(v_remaining, v_tier.max_minutes - v_consumed_normal);
        end if;

        if v_slice <= 0 then
          raise exception 'Érvénytelen progresszív díjsáv a snapshotban.' using errcode = 'P0001';
        end if;

        insert into public.settlement_booking_lines (
          settlement_revision_id, booking_id, duration_minutes, pricing_mode,
          pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
          pricing_scheme, line_kind
        ) values (
          v_revision_id, v_booking.id, v_slice, 'tiered',
          v_tier.id, v_tier.hourly_rate_huf,
          round(v_slice::numeric * v_tier.hourly_rate_huf / 60)::bigint,
          v_part, 'progressive', 'normal'
        );

        v_consumed_normal := v_consumed_normal + v_slice;
        v_remaining := v_remaining - v_slice;
        v_part := v_part + 1;
      end loop;
    end if;
  end loop;

  select coalesce(sum(sbl.amount_huf), 0), coalesce(sum(sbl.duration_minutes), 0)::integer
    into v_line_total, v_line_minutes
  from public.settlement_booking_lines sbl
  where sbl.settlement_revision_id = v_revision_id;

  if v_line_total <> v_calc.calculated_due_huf then
    raise exception 'A settlement sorok összege eltér a központi számítástól.' using errcode = 'P0001';
  end if;
  if v_line_minutes <> v_calc.normal_minutes + v_calc.special_minutes then
    raise exception 'A settlement sorok időtartama eltér a központi számítástól.' using errcode = 'P0001';
  end if;

  update public.monthly_settlements
  set is_closed = true,
      closed_at = now(),
      closed_by = v_actor,
      closed_revision_id = v_revision_id,
      updated_at = now()
  where id = v_settlement_id;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id,
    before_data, after_data, reason, correlation_id
  ) values (
    v_actor,
    'monthly_settlement.closed',
    'monthly_settlement',
    v_settlement_id::text,
    null,
    jsonb_build_object(
      'user_id', p_user_id,
      'settlement_month', p_settlement_month,
      'revision_id', v_revision_id,
      'revision_number', v_revision_number,
      'pricing_scheme', v_calc.pricing_scheme,
      'normal_minutes', v_calc.normal_minutes,
      'special_minutes', v_calc.special_minutes,
      'calculated_due_huf', v_calc.calculated_due_huf,
      'calculation_input_hash', v_calc.calculation_input_hash
    ),
    'Havi elszámolás lezárása',
    v_correlation_id
  );

  return query select v_settlement_id, v_revision_id, v_revision_number, v_calc.calculated_due_huf;
end;
$$;

revoke execute on function public.admin_close_monthly_settlement(uuid,date) from public, anon;
grant execute on function public.admin_close_monthly_settlement(uuid,date) to authenticated;

revoke execute on function public.prevent_settlement_snapshot_mutation() from public, anon, authenticated;

commit;
