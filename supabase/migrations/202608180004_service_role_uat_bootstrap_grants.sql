begin;

-- A Supabase 2026-os Data API alapértelmezés-változása óta új projekteken
-- a service_role sem kap automatikus táblaszintű jogot a public séma új tábláira.
-- Az RLS megkerülése (BYPASSRLS) ettől külön réteg: a PostgreSQL GRANT továbbra
-- is szükséges. Emiatt minden jövőbeli, service_role kulccsal közvetlenül
-- (nem SECURITY DEFINER RPC-n keresztül) elért táblához explicit, minimális
-- jogosultságot kell verziózott migrációban megadni.
--
-- Itt csak a staging UAT bootstrap által közvetlenül olvasott/írt táblák és
-- műveletek kapnak jogot; DELETE és üzleti foglalási/pénzügyi táblák nem.
grant select, update
on table public.profiles
to service_role;

grant select, insert, update
on table public.rooms,
  public.user_room_permissions,
  public.calendar_exceptions
to service_role;

comment on table public.profiles is
  'Üzleti userprofil az auth.users mellett; service_role csak staging UAT/admin backend célra kap szűk SELECT/UPDATE jogot.';

commit;
