begin;

-- The admin Felhasználók page reads this column through an authenticated
-- session. Keep least privilege: authenticated may SELECT the canonical repeat
-- flag, but direct UPDATE remains disallowed; changes go through the audited
-- admin_set_profile_repeat_permission RPC.
grant select (can_repeat_bookings) on public.profiles to authenticated;

commit;
