begin;

-- GitHub #261 / 2026-10-01 business correction:
-- the central monthly tier is selected from ALL active billable minutes of the
-- user in the month. Training-room group minutes participate in the tier base,
-- while the group booking itself keeps its special-room rate.
--
-- Keep the historical function name for compatibility with existing callers.
-- Its return value is now the monthly tier-base minutes, not "normal-only"
-- minutes. Reporting normal_minutes/special_minutes remains unchanged in
-- calculate_monthly_pricing().
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
  ), 0)::integer
  + greatest(coalesce(p_additional_minutes, 0), 0)
  from public.bookings booking
  where booking.user_id = p_user_id
    and booking.status = 'active'
    and booking.id is distinct from p_excluded_booking_id
    and (booking.start_at at time zone 'Europe/Budapest')::date >= p_month
    and (booking.start_at at time zone 'Europe/Budapest')::date < (p_month + interval '1 month')::date;
$$;

revoke all on function public.month_normal_minutes(uuid,date,uuid,integer,boolean)
  from public,anon,authenticated,service_role;

comment on function public.month_normal_minutes(uuid,date,uuid,integer,boolean) is
  'Internal monthly central-tier base in minutes. Includes all active billable bookings, including Training-room group bookings; historical name retained for compatibility.';

commit;
