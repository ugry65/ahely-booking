begin;

create type public.monthly_pricing_line_kind as enum ('normal', 'special_room', 'free');

create or replace function public.calculate_monthly_pricing(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
  normal_due_huf bigint,
  special_due_huf bigint,
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
  v_month_start date;
  v_month_end date;
  v_scheme public.user_pricing_scheme;
  v_normal_minutes integer := 0;
  v_special_minutes integer := 0;
  v_normal_due bigint := 0;
  v_special_due bigint := 0;
  v_fixed_rate bigint;
  v_tier record;
  v_remaining integer;
  v_slice integer;
  v_consumed integer := 0;
  v_breakdown jsonb := '[]'::jsonb;
  v_booking_digest text;
begin
  if p_user_id is null or not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  v_month_start := p_settlement_month;
  v_month_end := (p_settlement_month + interval '1 month')::date;
  v_scheme := public.effective_user_pricing_scheme(p_user_id, p_settlement_month);

  select override.hourly_rate_huf
    into v_fixed_rate
  from public.user_price_overrides override
  where override.user_id = p_user_id
    and p_settlement_month between override.valid_from and coalesce(override.valid_to, 'infinity'::date)
  order by override.valid_from desc
  limit 1;

  select
    coalesce(sum((extract(epoch from (b.end_at - b.start_at)) / 60)::integer) filter (
      where not (r.is_training_room and b.use_type = 'group')
    ), 0)::integer,
    coalesce(sum((extract(epoch from (b.end_at - b.start_at)) / 60)::integer) filter (
      where r.is_training_room and b.use_type = 'group'
    ), 0)::integer,
    md5(coalesce(string_agg(
      b.id::text || ':' || b.updated_at::text || ':' || b.status::text || ':' || b.start_at::text || ':' || b.end_at::text || ':' || b.use_type::text,
      '|' order by b.id
    ), ''))
  into v_normal_minutes, v_special_minutes, v_booking_digest
  from public.bookings b
  join public.rooms r on r.id = b.room_id
  where b.user_id = p_user_id
    and b.status = 'active'
    and (b.start_at at time zone 'Europe/Budapest')::date >= v_month_start
    and (b.start_at at time zone 'Europe/Budapest')::date < v_month_end;

  if v_scheme = 'free' then
    v_breakdown := jsonb_build_array(jsonb_build_object(
      'kind', 'free', 'minutes', v_normal_minutes + v_special_minutes, 'hourly_rate_huf', 0, 'amount_huf', 0
    ));
  else
    if v_fixed_rate is not null then
      v_normal_due := round(v_normal_minutes::numeric * v_fixed_rate / 60)::bigint;
      if v_normal_minutes > 0 then
        v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
          'kind', 'normal', 'mode', 'fixed_user', 'minutes', v_normal_minutes,
          'hourly_rate_huf', v_fixed_rate, 'amount_huf', v_normal_due
        ));
      end if;
    elsif v_scheme = 'tiered' then
      select t.id, t.min_minutes, t.max_minutes, t.hourly_rate_huf
        into v_tier
      from public.pricing_tiers t
      where v_normal_minutes between t.min_minutes and coalesce(t.max_minutes, 2147483647)
        and p_settlement_month between t.valid_from and coalesce(t.valid_to, 'infinity'::date)
      order by t.min_minutes desc
      limit 1;

      if v_normal_minutes > 0 and v_tier.id is null then
        raise exception 'Nincs érvényes díjsáv a havi óraszámhoz.' using errcode = 'P0001';
      end if;
      if v_normal_minutes > 0 then
        v_normal_due := round(v_normal_minutes::numeric * v_tier.hourly_rate_huf / 60)::bigint;
        v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
          'kind', 'normal', 'mode', 'tiered', 'pricing_rule_id', v_tier.id,
          'minutes', v_normal_minutes, 'hourly_rate_huf', v_tier.hourly_rate_huf, 'amount_huf', v_normal_due
        ));
      end if;
    else
      v_remaining := v_normal_minutes;
      v_consumed := 0;
      for v_tier in
        select t.id, t.min_minutes, t.max_minutes, t.hourly_rate_huf
        from public.pricing_tiers t
        where p_settlement_month between t.valid_from and coalesce(t.valid_to, 'infinity'::date)
        order by t.min_minutes
      loop
        exit when v_remaining <= 0;
        if v_tier.max_minutes is null then
          v_slice := v_remaining;
        else
          v_slice := least(v_remaining, greatest(v_tier.max_minutes - v_consumed, 0));
        end if;
        if v_slice > 0 then
          v_normal_due := v_normal_due + round(v_slice::numeric * v_tier.hourly_rate_huf / 60)::bigint;
          v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
            'kind', 'normal', 'mode', 'progressive', 'pricing_rule_id', v_tier.id,
            'minutes', v_slice, 'hourly_rate_huf', v_tier.hourly_rate_huf,
            'amount_huf', round(v_slice::numeric * v_tier.hourly_rate_huf / 60)::bigint
          ));
          v_remaining := v_remaining - v_slice;
          v_consumed := v_consumed + v_slice;
        end if;
      end loop;
      if v_remaining > 0 then
        raise exception 'A progresszív díjsávok nem fedik le a havi óraszámot.' using errcode = 'P0001';
      end if;
    end if;

    if v_special_minutes > 0 then
      select rate.id, rate.hourly_rate_huf
        into v_tier
      from public.special_room_rates rate
      join public.rooms r on r.id = rate.room_id
      where r.is_training_room
        and rate.use_type = 'group'
        and p_settlement_month between rate.valid_from and coalesce(rate.valid_to, 'infinity'::date)
      order by rate.valid_from desc
      limit 1;
      if v_tier.id is null then
        raise exception 'Nincs érvényes Tréningterem csoportos díj.' using errcode = 'P0001';
      end if;
      v_special_due := round(v_special_minutes::numeric * v_tier.hourly_rate_huf / 60)::bigint;
      v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
        'kind', 'special_room', 'pricing_rule_id', v_tier.id, 'minutes', v_special_minutes,
        'hourly_rate_huf', v_tier.hourly_rate_huf, 'amount_huf', v_special_due
      ));
    end if;
  end if;

  return query select
    p_user_id,
    p_settlement_month,
    v_scheme,
    v_normal_minutes,
    v_special_minutes,
    v_normal_due,
    v_special_due,
    v_normal_due + v_special_due,
    v_breakdown,
    encode(extensions.digest(
      p_user_id::text || '|' || p_settlement_month::text || '|' || v_scheme::text || '|' ||
      coalesce(v_fixed_rate::text, '') || '|' || v_normal_minutes::text || '|' || v_special_minutes::text || '|' ||
      coalesce(v_booking_digest, '') || '|' || v_breakdown::text,
      'sha256'
    ), 'hex');
end;
$$;

revoke execute on function public.calculate_monthly_pricing(uuid,date) from public, anon, authenticated;

create or replace function public.admin_calculate_monthly_pricing(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
  normal_due_huf bigint,
  special_due_huf bigint,
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

create or replace function public.get_my_monthly_pricing(
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
  normal_due_huf bigint,
  special_due_huf bigint,
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
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not exists (
    select 1 from public.profiles p
    where p.id = v_user_id and p.is_active and p.dashboard_enabled
  ) then
    raise exception 'A havi elszámolási dashboard nem érhető el.' using errcode = '42501';
  end if;
  return query select * from public.calculate_monthly_pricing(v_user_id, p_settlement_month);
end;
$$;

revoke execute on function public.admin_calculate_monthly_pricing(uuid,date) from public, anon;
revoke execute on function public.get_my_monthly_pricing(date) from public, anon;
grant execute on function public.admin_calculate_monthly_pricing(uuid,date) to authenticated;
grant execute on function public.get_my_monthly_pricing(date) to authenticated;

commit;
