-- Stop automatic legacy defaults; preserve every historical booking rate.
begin;
set local lock_timeout = '3s';
drop trigger if exists bookings_training_group_rate_default on public.bookings;
commit;
