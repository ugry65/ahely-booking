begin;

create or replace function public.admin_monthly_active_booking_details(
  p_month date,
  p_user_id uuid default null
)
returns table (
  booking_id uuid,
  user_id uuid,
  user_name text,
  booking_date date,
  room_name text,
  start_time time,
  end_time time,
  total_minutes bigint,
  total_hours numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date;
begin
  perform public.require_active_admin();
  if p_month is null then
    raise exception 'Az elszámolási hónap kötelező.' using errcode = '22004';
  end if;
  v_month := date_trunc('month', p_month)::date;

  return query
  select
    booking.id,
    profile.id,
    profile.last_name || ' ' || profile.first_name,
    (booking.start_at at time zone 'Europe/Budapest')::date,
    room.name,
    (booking.start_at at time zone 'Europe/Budapest')::time,
    (booking.end_at at time zone 'Europe/Budapest')::time,
    (extract(epoch from (booking.end_at - booking.start_at)) / 60)::bigint,
    round(extract(epoch from (booking.end_at - booking.start_at)) / 3600, 2)
  from public.bookings booking
  join public.profiles profile on profile.id = booking.user_id
  join public.rooms room on room.id = booking.room_id
  where booking.status = 'active'
    and (booking.start_at at time zone 'Europe/Budapest')::date >= v_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (v_month + interval '1 month')::date
    and (p_user_id is null or booking.user_id = p_user_id)
  order by profile.last_name, profile.first_name,
    (booking.start_at at time zone 'Europe/Budapest')::date,
    booking.start_at, room.display_order, booking.id;
end;
$$;

create or replace function public.admin_cancellation_summary(
  p_end_month date,
  p_months integer
)
returns table (
  user_id uuid,
  user_name text,
  total_bookings bigint,
  cancelled_count bigint,
  cancelled_hours numeric,
  user_cancelled_count bigint,
  user_cancelled_hours numeric,
  cancellation_rate numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_end_month date;
  v_start_month date;
begin
  perform public.require_active_admin();
  if p_end_month is null then
    raise exception 'A záró hónap kötelező.' using errcode = '22004';
  end if;
  if p_months not in (1, 3, 6, 12) then
    raise exception 'Az időszak csak 1, 3, 6 vagy 12 hónap lehet.' using errcode = '22023';
  end if;

  v_end_month := date_trunc('month', p_end_month)::date;
  v_start_month := (v_end_month - make_interval(months => p_months - 1))::date;

  return query
  select
    profile.id,
    profile.last_name || ' ' || profile.first_name,
    count(booking.id)::bigint,
    count(booking.id) filter (where booking.status = 'cancelled')::bigint,
    round(coalesce(sum(extract(epoch from (booking.end_at - booking.start_at)))
      filter (where booking.status = 'cancelled'), 0) / 3600, 2),
    count(booking.id) filter (
      where booking.status = 'cancelled' and cancellation.cancelled_by = booking.user_id
    )::bigint,
    round(coalesce(sum(extract(epoch from (booking.end_at - booking.start_at))) filter (
      where booking.status = 'cancelled' and cancellation.cancelled_by = booking.user_id
    ), 0) / 3600, 2),
    case when count(booking.id) = 0 then 0::numeric
      else round(
        100.0 * count(booking.id) filter (
          where booking.status = 'cancelled' and cancellation.cancelled_by = booking.user_id
        ) / count(booking.id),
        1
      )
    end
  from public.bookings booking
  join public.profiles profile on profile.id = booking.user_id
  left join public.booking_cancellations cancellation on cancellation.booking_id = booking.id
  where booking.status in ('active', 'cancelled')
    and (booking.start_at at time zone 'Europe/Budapest')::date >= v_start_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (v_end_month + interval '1 month')::date
  group by profile.id, profile.last_name, profile.first_name
  order by profile.last_name, profile.first_name, profile.id;
end;
$$;

create or replace function public.admin_cancellation_details(
  p_end_month date,
  p_months integer,
  p_user_id uuid default null
)
returns table (
  booking_id uuid,
  user_id uuid,
  user_name text,
  booking_date date,
  room_name text,
  start_time time,
  end_time time,
  cancelled_hours numeric,
  cancelled_at timestamptz,
  minutes_before_start integer,
  cancellation_reason text,
  cancelled_by_user boolean,
  cancelled_by_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_end_month date;
  v_start_month date;
begin
  perform public.require_active_admin();
  if p_end_month is null then
    raise exception 'A záró hónap kötelező.' using errcode = '22004';
  end if;
  if p_months not in (1, 3, 6, 12) then
    raise exception 'Az időszak csak 1, 3, 6 vagy 12 hónap lehet.' using errcode = '22023';
  end if;

  v_end_month := date_trunc('month', p_end_month)::date;
  v_start_month := (v_end_month - make_interval(months => p_months - 1))::date;

  return query
  select
    booking.id,
    profile.id,
    profile.last_name || ' ' || profile.first_name,
    (booking.start_at at time zone 'Europe/Budapest')::date,
    room.name,
    (booking.start_at at time zone 'Europe/Budapest')::time,
    (booking.end_at at time zone 'Europe/Budapest')::time,
    round(extract(epoch from (booking.end_at - booking.start_at)) / 3600, 2),
    cancellation.cancelled_at,
    cancellation.minutes_before_start,
    cancellation.reason,
    cancellation.cancelled_by = booking.user_id,
    cancel_actor.last_name || ' ' || cancel_actor.first_name
  from public.bookings booking
  join public.profiles profile on profile.id = booking.user_id
  join public.rooms room on room.id = booking.room_id
  join public.booking_cancellations cancellation on cancellation.booking_id = booking.id
  join public.profiles cancel_actor on cancel_actor.id = cancellation.cancelled_by
  where booking.status = 'cancelled'
    and (booking.start_at at time zone 'Europe/Budapest')::date >= v_start_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (v_end_month + interval '1 month')::date
    and (p_user_id is null or booking.user_id = p_user_id)
  order by profile.last_name, profile.first_name,
    (booking.start_at at time zone 'Europe/Budapest')::date,
    booking.start_at, booking.id;
end;
$$;

revoke all on function public.admin_monthly_active_booking_details(date,uuid) from public, anon;
revoke all on function public.admin_cancellation_summary(date,integer) from public, anon;
revoke all on function public.admin_cancellation_details(date,integer,uuid) from public, anon;
grant execute on function public.admin_monthly_active_booking_details(date,uuid) to authenticated, service_role;
grant execute on function public.admin_cancellation_summary(date,integer) to authenticated, service_role;
grant execute on function public.admin_cancellation_details(date,integer,uuid) to authenticated, service_role;

comment on function public.admin_monthly_active_booking_details(date,uuid) is
  'Admin tételes elszámolási ellenőrzés: kizárólag aktív foglalások, Europe/Budapest hónaphatárral.';
comment on function public.admin_cancellation_summary(date,integer) is
  'Admin lemondási statisztika 1/3/6/12 havi időszakra; a user lemondási aránya csak a user saját maga által lemondott foglalásokat számítja a user terhére.';
comment on function public.admin_cancellation_details(date,integer,uuid) is
  'Admin tételes lemondási auditlista, a lemondó személyével és az eredeti foglalási időponttal.';

commit;
