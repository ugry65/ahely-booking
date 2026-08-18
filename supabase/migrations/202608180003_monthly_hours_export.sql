begin;

create or replace function public.admin_monthly_booking_hours(p_month date)
returns table (
  user_id uuid,
  user_name text,
  email text,
  booking_count bigint,
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
  select profile.id,
    profile.last_name || ' ' || profile.first_name,
    profile.email,
    count(booking.id),
    (sum(extract(epoch from (booking.end_at - booking.start_at))) / 60)::bigint,
    round(sum(extract(epoch from (booking.end_at - booking.start_at))) / 3600, 2)
  from public.bookings booking
  join public.profiles profile on profile.id = booking.user_id
  where booking.status = 'active'
    and (booking.start_at at time zone 'Europe/Budapest')::date >= v_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (v_month + interval '1 month')::date
  group by profile.id, profile.last_name, profile.first_name, profile.email
  order by profile.last_name, profile.first_name, profile.id;
end;
$$;

revoke all on function public.admin_monthly_booking_hours(date) from public, anon;
grant execute on function public.admin_monthly_booking_hours(date) to authenticated;

comment on function public.admin_monthly_booking_hours(date) is
  'Aktív admin havi, userenkénti foglalásszám- és óraszám-kimutatása Europe/Budapest hónaphatárral; díjszámítást nem végez.';

commit;
