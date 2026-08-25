begin;

drop function if exists public.admin_monthly_active_booking_details(date, uuid);

create function public.admin_monthly_active_booking_details(
  p_month date,
  p_user_id uuid default null
)
returns table (
  booking_id uuid,
  user_id uuid,
  user_name text,
  booking_date date,
  room_name text,
  booking_title text,
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
    booking.title,
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

revoke all on function public.admin_monthly_active_booking_details(date,uuid) from public, anon;
grant execute on function public.admin_monthly_active_booking_details(date,uuid) to authenticated, service_role;

comment on function public.admin_monthly_active_booking_details(date,uuid) is
  'Admin tételes elszámolási ellenőrzés: kizárólag aktív foglalások, Europe/Budapest hónaphatárral; a foglalás címe is visszaadódik az admin ellenőrzéshez és exporthoz.';

commit;
