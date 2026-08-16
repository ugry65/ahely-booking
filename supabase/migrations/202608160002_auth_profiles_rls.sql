begin;

create or replace function public.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_active
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and is_active
      and role = 'admin'
  );
$$;

create or replace function public.sync_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is null then
    raise exception 'A-Hely only supports users with an email address' using errcode = '23502';
  end if;

  if tg_op = 'INSERT' then
    insert into public.profiles (
      id,
      first_name,
      last_name,
      email,
      role,
      is_active
    ) values (
      new.id,
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''),
        split_part(lower(new.email), '@', 1)
      ),
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), ''),
      lower(new.email),
      'user',
      true
    );
  elsif new.email is distinct from old.email then
    update public.profiles
    set email = lower(new.email), updated_at = now()
    where id = new.id;
  end if;

  return new;
end;
$$;

create trigger auth_user_profile_sync
after insert or update of email on auth.users
for each row execute function public.sync_auth_user_profile();

create policy profiles_select_own_or_admin
on public.profiles
for select
to authenticated
using (
  public.is_active_user()
  and (id = auth.uid() or public.is_admin())
);

create policy rooms_select_active_users
on public.rooms
for select
to authenticated
using (public.is_active_user());

create policy settings_select_active_users
on public.app_settings
for select
to authenticated
using (public.is_active_user());

create policy opening_hours_select_active_users
on public.weekly_opening_hours
for select
to authenticated
using (public.is_active_user());

create policy calendar_exceptions_select_active_users
on public.calendar_exceptions
for select
to authenticated
using (public.is_active_user());

-- A Data API minden joga explicit. Az adminisztratív és üzleti írások
-- későbbi, szűk RPC-ken vagy ellenőrzött szerveroldali műveleteken át mennek.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant usage on schema public to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;

grant select (
  id, first_name, last_name, email, phone, organization, role, is_active,
  dashboard_enabled, other_booker_names_visible, advance_booking_days_override,
  created_at, updated_at
) on public.profiles to authenticated;

grant select (id, name, is_active, display_order, is_training_room, created_at, updated_at)
on public.rooms to authenticated;

grant select (key, value, description, updated_at)
on public.app_settings to authenticated;

grant select (iso_weekday, opens_at, closes_at, is_closed)
on public.weekly_opening_hours to authenticated;

grant select (service_date, opens_at, closes_at, is_closed, reason, created_at)
on public.calendar_exceptions to authenticated;

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

comment on function public.is_active_user() is
  'A valid JWT userhez tartozó aktív üzleti profil ellenőrzése; RLS policykhez.';
comment on function public.is_admin() is
  'Az aktív adminszerepet mindig a profiles táblából ellenőrzi, nem JWT metadata alapján.';
comment on function public.sync_auth_user_profile() is
  'Meghívott Auth userhez normál, aktív profilt hoz létre; kliensmetadata nem adhat adminszerepet.';

commit;
