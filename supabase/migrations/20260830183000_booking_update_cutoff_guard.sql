begin;

create or replace function public.guard_booking_update_cutoff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.app_role;
  v_cutoff_hours integer;
begin
  -- A cutoff a normál user által végzett élő foglalásmódosítást védi.
  -- Lemondáskor a status active -> cancelled váltás külön RPC-szabályt használ,
  -- ezért azt ez a trigger nem blokkolja. Csak az eredeti aktív állapot számít:
  -- így egy jövőbeli, kombinált status + időmező UPDATE sem kerülheti meg a guardot.
  if old.status <> 'active' then
    return new;
  end if;

  select role
  into v_actor_role
  from public.profiles
  where id = v_actor_id
    and is_active;

  -- A megbízható belső/service műveleteknek nincs auth.uid()-juk. A kliensoldali
  -- booking write továbbra is RLS/RPC határ mögött van; a normál felhasználói
  -- hívásoknál az actor profil kötelezően feloldható. Ezt a szándékos bypass ágat
  -- külön pgTAP regressziós teszt védi.
  if v_actor_id is null then
    return new;
  end if;

  if v_actor_role is null then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if v_actor_role = 'admin' then
    return new;
  end if;

  select (value #>> '{}')::integer
  into v_cutoff_hours
  from public.app_settings
  where key = 'cancellation_cutoff_hours';

  if v_cutoff_hours is null or v_cutoff_hours < 0 then
    raise exception 'A lemondási határidő beállítása hiányzik vagy hibás.' using errcode = 'P0001';
  end if;

  -- Az EREDETI kezdést vizsgáljuk. Így egy cutoffon belüli foglalást nem lehet
  -- előbb későbbre tolni, majd az új időpont alapján lemondani.
  if clock_timestamp() > old.start_at - make_interval(hours => v_cutoff_hours) then
    raise exception 'A foglalás % órán belül már nem módosítható.', v_cutoff_hours using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger bookings_guard_update_cutoff
before update of room_id, start_at, end_at, use_type, note on public.bookings
for each row
when (
  old.status = 'active'
  and (
    old.room_id is distinct from new.room_id
    or old.start_at is distinct from new.start_at
    or old.end_at is distinct from new.end_at
    or old.use_type is distinct from new.use_type
    or old.note is distinct from new.note
  )
)
execute function public.guard_booking_update_cutoff();

revoke all on function public.guard_booking_update_cutoff() from public, anon, authenticated;

comment on function public.guard_booking_update_cutoff() is
  'DB-szintű regresszióvédelem: normál user az eredeti start_at alapján cutoffon belüli aktív foglalást nem módosíthat; admin és megbízható auth.uid() nélküli service/internal művelet bypass. Lezárja a módosítás -> későbbre tolás -> lemondás kerülőutat.';

commit;
