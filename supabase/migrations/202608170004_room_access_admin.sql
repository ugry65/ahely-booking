begin;

alter table public.user_room_permissions
  add constraint user_room_permissions_repeat_requires_booking
  check (not can_repeat or can_book);

alter table public.access_group_rooms
  add constraint access_group_rooms_repeat_requires_booking
  check (not can_repeat or can_book);

create or replace function public.require_active_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
begin
  if v_actor_id is null or not public.is_admin() then
    raise exception 'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.'
      using errcode = '42501';
  end if;
  return v_actor_id;
end;
$$;

create or replace function public.admin_upsert_room(
  p_room_id uuid,
  p_name text,
  p_display_order integer,
  p_is_training_room boolean,
  p_is_active boolean,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_room_id uuid := coalesce(p_room_id, gen_random_uuid());
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'A helyiség neve kötelező.' using errcode = '22023';
  end if;
  if p_display_order is null or p_display_order < 0 then
    raise exception 'A megjelenítési sorrend nem lehet negatív.' using errcode = '22023';
  end if;

  select to_jsonb(room) into v_before
  from public.rooms room where room.id = v_room_id for update;

  insert into public.rooms (id, name, display_order, is_training_room, is_active)
  values (v_room_id, btrim(p_name), p_display_order, coalesce(p_is_training_room, false), coalesce(p_is_active, true))
  on conflict (id) do update set
    name = excluded.name,
    display_order = excluded.display_order,
    is_training_room = excluded.is_training_room,
    is_active = excluded.is_active,
    updated_at = now()
  where (rooms.name, rooms.display_order, rooms.is_training_room, rooms.is_active)
    is distinct from (excluded.name, excluded.display_order, excluded.is_training_room, excluded.is_active);

  select to_jsonb(room) into v_after from public.rooms room where room.id = v_room_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id, case when v_before is null then 'room.created' else 'room.updated' end,
      'room', v_room_id::text, v_before, v_after, p_correlation_id
    );
  end if;
  return v_room_id;
exception when unique_violation then
  raise exception 'Már létezik helyiség ezzel a névvel.' using errcode = 'P0001';
end;
$$;

create or replace function public.admin_set_user_room_permission(
  p_user_id uuid,
  p_room_id uuid,
  p_can_book boolean,
  p_can_repeat boolean,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004'; end if;
  if coalesce(p_can_repeat, false) and not coalesce(p_can_book, false) then
    raise exception 'Ismétlődő foglalási jog csak foglalási jog mellett adható.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'A helyiség nem található.' using errcode = 'P0001';
  end if;

  -- A még nem létező összetett kulcsú sort SELECT ... FOR UPDATE nem tudná
  -- zárolni. Az advisory lock ugyanarra a user-room párra sorba rendezi az
  -- első létrehozásokat is, így a before/after audit pontos marad.
  perform pg_advisory_xact_lock(hashtextextended(
    'user_room_permission:' || p_user_id::text || ':' || p_room_id::text, 0
  ));

  select to_jsonb(permission) into v_before from public.user_room_permissions permission
  where user_id = p_user_id and room_id = p_room_id for update;
  insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat)
  values (p_user_id, p_room_id, coalesce(p_can_book, false), coalesce(p_can_repeat, false))
  on conflict (user_id, room_id) do update set can_book = excluded.can_book, can_repeat = excluded.can_repeat;
  select to_jsonb(permission) into v_after from public.user_room_permissions permission
  where user_id = p_user_id and room_id = p_room_id;

  if v_before is distinct from v_after then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (v_actor_id, 'user_room_permission.set', 'user_room_permission', p_user_id::text || ':' || p_room_id::text,
      v_before, v_after, p_correlation_id);
  end if;
end;
$$;

create or replace function public.admin_upsert_access_group(
  p_group_id uuid,
  p_name text,
  p_is_active boolean,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_group_id uuid := coalesce(p_group_id, gen_random_uuid());
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'A csoport neve kötelező.' using errcode = '22023'; end if;
  select to_jsonb(access_group) into v_before from public.access_groups access_group where id = v_group_id for update;
  insert into public.access_groups (id, name, is_active)
  values (v_group_id, btrim(p_name), coalesce(p_is_active, true))
  on conflict (id) do update set name = excluded.name, is_active = excluded.is_active;
  select to_jsonb(access_group) into v_after from public.access_groups access_group where id = v_group_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (v_actor_id, case when v_before is null then 'access_group.created' else 'access_group.updated' end,
      'access_group', v_group_id::text, v_before, v_after, p_correlation_id);
  end if;
  return v_group_id;
exception when unique_violation then
  raise exception 'Már létezik hozzáférési csoport ezzel a névvel.' using errcode = 'P0001';
end;
$$;

create or replace function public.admin_set_group_member(
  p_group_id uuid,
  p_user_id uuid,
  p_is_member boolean,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004'; end if;
  if not exists (select 1 from public.access_groups where id = p_group_id) then raise exception 'A csoport nem található.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then raise exception 'A felhasználó nem található.' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'access_group_member:' || p_group_id::text || ':' || p_user_id::text, 0
  ));
  select to_jsonb(member) into v_before from public.access_group_members member
  where group_id = p_group_id and user_id = p_user_id for update;
  if coalesce(p_is_member, false) then
    insert into public.access_group_members (group_id, user_id) values (p_group_id, p_user_id)
    on conflict do nothing;
  else
    delete from public.access_group_members where group_id = p_group_id and user_id = p_user_id;
  end if;
  select to_jsonb(member) into v_after from public.access_group_members member
  where group_id = p_group_id and user_id = p_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (v_actor_id, case when v_after is null then 'access_group_member.removed' else 'access_group_member.added' end,
      'access_group_member', p_group_id::text || ':' || p_user_id::text, v_before, v_after, p_correlation_id);
  end if;
end;
$$;

create or replace function public.admin_set_group_room_permission(
  p_group_id uuid,
  p_room_id uuid,
  p_can_book boolean,
  p_can_repeat boolean,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before jsonb;
  v_after jsonb;
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004'; end if;
  if coalesce(p_can_repeat, false) and not coalesce(p_can_book, false) then
    raise exception 'Ismétlődő foglalási jog csak foglalási jog mellett adható.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.access_groups where id = p_group_id) then raise exception 'A csoport nem található.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then raise exception 'A helyiség nem található.' using errcode = 'P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'access_group_room_permission:' || p_group_id::text || ':' || p_room_id::text, 0
  ));
  select to_jsonb(permission) into v_before from public.access_group_rooms permission
  where group_id = p_group_id and room_id = p_room_id for update;
  insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat)
  values (p_group_id, p_room_id, coalesce(p_can_book, false), coalesce(p_can_repeat, false))
  on conflict (group_id, room_id) do update set can_book = excluded.can_book, can_repeat = excluded.can_repeat;
  select to_jsonb(permission) into v_after from public.access_group_rooms permission
  where group_id = p_group_id and room_id = p_room_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (v_actor_id, 'access_group_room_permission.set', 'access_group_room_permission',
      p_group_id::text || ':' || p_room_id::text, v_before, v_after, p_correlation_id);
  end if;
end;
$$;

revoke execute on function public.require_active_admin() from public, anon, authenticated;
revoke execute on function public.admin_upsert_room(uuid,text,integer,boolean,boolean,uuid) from public, anon;
revoke execute on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) from public, anon;
revoke execute on function public.admin_upsert_access_group(uuid,text,boolean,uuid) from public, anon;
revoke execute on function public.admin_set_group_member(uuid,uuid,boolean,uuid) from public, anon;
revoke execute on function public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid) from public, anon;
grant execute on function public.admin_upsert_room(uuid,text,integer,boolean,boolean,uuid) to authenticated;
grant execute on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) to authenticated;
grant execute on function public.admin_upsert_access_group(uuid,text,boolean,uuid) to authenticated;
grant execute on function public.admin_set_group_member(uuid,uuid,boolean,uuid) to authenticated;
grant execute on function public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid) to authenticated;

commit;
