-- The profiles table already uses RLS (own profile or admin only).
-- Adataim now reads the user's current calendar color so it can mark the selected palette item.
grant select (calendar_color) on public.profiles to authenticated;
