begin;

-- Authenticated clients have no direct table privileges or RLS policy on
-- user_room_permissions. Legacy compatibility is intentionally supported only
-- through the audited admin_set_user_room_permission RPC. A table trigger would
-- introduce an unsupported direct-SQL path whose row-lock -> profile-lock order
-- could deadlock with the canonical profile-first repeat-permission OFF path.
drop trigger if exists promote_user_repeat_permission_from_legacy
  on public.user_room_permissions;

drop function if exists public.promote_user_repeat_permission_from_legacy();

-- Least privilege: this focused admin RPC is only needed through authenticated
-- application sessions. service_role keeps its broader database access, but does
-- not need a dedicated EXECUTE grant on this authorization-changing entry point.
revoke execute on function public.admin_set_profile_repeat_permission(uuid,boolean,uuid) from service_role;

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
  v_profile_repeat_before boolean;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if coalesce(p_can_repeat, false) and not coalesce(p_can_book, false) then
    raise exception 'Ismétlődő foglalási jog csak foglalási jog mellett adható.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'A helyiség nem található.' using errcode = 'P0001';
  end if;

  -- Canonical lock order: profile-level repeat state first, then the individual
  -- room-permission row. This is shared with admin_set_profile_repeat_permission.
  perform pg_advisory_xact_lock(hashtextextended(
    'profile_repeat_permission:' || p_user_id::text, 0
  ));

  select profile.can_repeat_bookings
  into v_profile_repeat_before
  from public.profiles profile
  where profile.id = p_user_id
  for update;

  if not found then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;

  -- A legacy TRUE signal promotes the canonical user-level permission. FALSE is
  -- only a legacy row value and must never switch the user-level permission off.
  if coalesce(p_can_repeat, false) and not v_profile_repeat_before then
    update public.profiles
    set can_repeat_bookings = true,
        updated_at = now()
    where id = p_user_id;

    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id,
      'profile.repeat_permission.set',
      'profile',
      p_user_id::text,
      jsonb_build_object('can_repeat_bookings', false),
      jsonb_build_object('can_repeat_bookings', true),
      p_correlation_id
    );
  end if;

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
      v_actor_id,
      'user_room_permission.set',
      'user_room_permission',
      p_user_id::text || ':' || p_room_id::text,
      v_before,
      v_after,
      p_correlation_id
    );
  end if;
end;
$$;

comment on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) is
  'Auditált kompatibilitási admin RPC közvetlen user–szoba joghoz. A legacy can_repeat=true ugyanebben a profile-first tranzakcióban user-szintű repeat jogot kapcsol be; közvetlen kliens-táblaírás nem támogatott.';

commit;
