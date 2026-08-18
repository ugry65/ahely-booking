begin;

-- A service_role RLS-t megkerülő szerveroldali szerep, de a PostgreSQL
-- táblaszintű jogosultságokat továbbra is explicit meg kell kapnia.
-- Csak a staging UAT bootstrap által közvetlenül olvasott/írt táblák és
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
