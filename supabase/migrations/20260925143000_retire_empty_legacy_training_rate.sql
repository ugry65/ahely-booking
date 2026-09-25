begin;

-- Compatibility bridge for the historical 2026-08 pricing chain.
-- Deployed databases that already carry a booking-level historical Training-room
-- rate must keep the legacy column so those immutable financial facts remain
-- available to resolve_booking_applied_rate().
-- Fresh databases (and production before pricing rollout) have no such values;
-- there the legacy write path must not be reintroduced.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bookings'
      and column_name = 'group_hourly_rate_huf'
  ) and not exists (
    select 1 from public.bookings
    where group_hourly_rate_huf is not null
  ) then
    drop trigger if exists bookings_training_group_rate_default on public.bookings;
    drop function if exists public.admin_set_booking_group_rate(uuid,bigint,uuid);
    drop function if exists public.apply_training_group_booking_rate();
    alter table public.bookings drop column group_hourly_rate_huf;
  end if;
end;
$$;

commit;
