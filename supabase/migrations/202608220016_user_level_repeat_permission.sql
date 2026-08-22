begin;

alter table public.profiles
  add column if not exists can_repeat_bookings boolean not null default false;

-- Preserve the effective meaning of every legacy per-room repeat grant: if a user
-- previously had repeat permission anywhere, the new user-level permission starts ON.
update public.profiles profile
set can_repeat_bookings = true
where not profile.can_repeat_bookings
  and exists (
    select 1
    from public.user_room_permissions legacy
    where legacy.user_id = profile.id
      and legacy.can_repeat
  );

-- Legacy direct writes/API clients may still set user_room_permissions.can_repeat.
-- Treat that bit only as a compatibility signal that promotes the canonical
-- USER-level permission. It no longer limits repeat permission to one room.
create or replace function public.promote_user_repeat_permission_from_legacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.can_repeat then
    update public.profiles
    set can_repeat_bookings = true,
        updated_at = now()
    where id = new.user_id
      and not can_repeat_bookings;
  end if;
  return new;
end;
$$;

drop trigger if exists promote_user_repeat_permission_from_legacy on public.user_room_permissions;
create trigger promote_user_repeat_permission_from_legacy
after insert or update of can_repeat on public.user_room_permissions
for each row
when (new.can_repeat)
execute function public.promote_user_repeat_permission_from_legacy();

revoke all on function public.promote_user_repeat_permission_from_legacy() from public, anon, authenticated;

create or replace function public.effective_room_permissions(p_user_id uuid)
returns table (
  room_id uuid,
  can_book boolean,
  can_repeat boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with actor as (
    select profile.can_repeat_bookings
    from public.profiles profile
    where profile.id = p_user_id
  ),
  booking_access as (
    select permission.room_id,
           bool_or(permission.can_book) as can_book
    from (
      select direct_permission.room_id,
             direct_permission.can_book
      from public.user_room_permissions direct_permission
      where direct_permission.user_id = p_user_id

      union all

      select group_permission.room_id,
             group_permission.can_book
      from public.access_group_members membership
      join public.access_groups access_group
        on access_group.id = membership.group_id
       and access_group.is_active
      join public.access_group_rooms group_permission
        on group_permission.group_id = membership.group_id
      where membership.user_id = p_user_id
    ) permission
    group by permission.room_id
  )
  select access.room_id,
         access.can_book,
         access.can_book
           and coalesce(actor.can_repeat_bookings, false)
           and not room.is_training_room as can_repeat
  from booking_access access
  join public.rooms room on room.id = access.room_id
  cross join actor
$$;

create or replace function public.list_repeatable_rooms()
returns table (room_id uuid, room_name text, is_training_room boolean, display_order integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  return query
  select room.id, room.name, room.is_training_room, room.display_order
  from public.rooms room
  where room.is_active
    and (
      v_actor.role = 'admin'
      or (
        v_actor.can_repeat_bookings
        and not room.is_training_room
        and exists (
          select 1
          from public.effective_room_permissions(v_actor.id) permission
          where permission.room_id = room.id
            and permission.can_book
        )
      )
    )
  order by room.display_order, room.name, room.id;
end;
$$;

create or replace function public.admin_set_profile_repeat_permission(
  p_user_id uuid,
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
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'profile_repeat_permission:' || p_user_id::text, 0
  ));

  select jsonb_build_object('can_repeat_bookings', profile.can_repeat_bookings)
  into v_before
  from public.profiles profile
  where profile.id = p_user_id
  for update;

  if v_before is null then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;

  update public.profiles
  set can_repeat_bookings = coalesce(p_can_repeat, false),
      updated_at = now()
  where id = p_user_id;

  -- Once the user-level permission is explicitly switched off, stale legacy
  -- per-room repeat flags must not be able to re-enable it through old data.
  if not coalesce(p_can_repeat, false) then
    update public.user_room_permissions
    set can_repeat = false
    where user_id = p_user_id
      and can_repeat;
  end if;

  select jsonb_build_object('can_repeat_bookings', profile.can_repeat_bookings)
  into v_after
  from public.profiles profile
  where profile.id = p_user_id;

  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id,
      'profile.repeat_permission.set',
      'profile',
      p_user_id::text,
      v_before,
      v_after,
      p_correlation_id
    );
  end if;
end;
$$;

-- Backward-compatible room-permission RPC. The old p_can_repeat bit is retained
-- in the legacy row and, when true, promotes the USER-level permission through
-- the compatibility trigger. Effective repeat semantics are nevertheless user-level.
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

  -- Keep a single lock order for the canonical user-level repeat switch and
  -- legacy room-level compatibility writes: profile first, room second.
  perform pg_advisory_xact_lock(hashtextextended(
    'profile_repeat_permission:' || p_user_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'user_room_permission:' || p_user_id::text || ':' || p_room_id::text, 0
  ));

  select to_jsonb(permission) into v_before
  from public.user_room_permissions permission
  where user_id = p_user_id and room_id = p_room_id
  for update;

  insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat)
  values (p_user_id, p_room_id, coalesce(p_can_book, false), coalesce(p_can_repeat, false))
  on conflict (user_id, room_id) do update set
    can_book = excluded.can_book,
    can_repeat = excluded.can_repeat;

  select to_jsonb(permission) into v_after
  from public.user_room_permissions permission
  where user_id = p_user_id and room_id = p_room_id;

  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id, 'user_room_permission.set', 'user_room_permission',
      p_user_id::text || ':' || p_room_id::text,
      v_before, v_after, p_correlation_id
    );
  end if;
end;
$$;

revoke all on function public.effective_room_permissions(uuid) from public, anon, authenticated;
revoke all on function public.list_repeatable_rooms() from public, anon;
grant execute on function public.list_repeatable_rooms() to authenticated;

revoke all on function public.admin_set_profile_repeat_permission(uuid,boolean,uuid) from public, anon;
grant execute on function public.admin_set_profile_repeat_permission(uuid,boolean,uuid) to authenticated, service_role;

revoke execute on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) from public, anon;
grant execute on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) to authenticated;

comment on column public.profiles.can_repeat_bookings is
  'User-szintű ismétlődő foglalási jogosultság. Normál user minden foglalható normál szobában ismételhet; Tréningterem kivétel.';
comment on function public.effective_room_permissions(uuid) is
  'Effektív helyiségjog: can_book közvetlen vagy aktív helyiségcsoportból; can_repeat user-szintű profiljogból minden foglalható nem-Tréningterem szobára.';
comment on function public.admin_set_profile_repeat_permission(uuid,boolean,uuid) is
  'Auditált admin művelet a user-szintű ismétlődő foglalási jogosultság kezelésére.';

commit;
