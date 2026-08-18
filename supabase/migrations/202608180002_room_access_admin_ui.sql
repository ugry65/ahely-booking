begin;

create or replace function public.admin_room_access_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();

  return jsonb_build_object(
    'rooms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', room.id, 'name', room.name, 'display_order', room.display_order,
        'is_training_room', room.is_training_room, 'is_active', room.is_active
      ) order by room.display_order, room.name, room.id)
      from public.rooms room
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', profile.id, 'name', profile.last_name || ' ' || profile.first_name,
        'email', profile.email, 'is_active', profile.is_active
      ) order by profile.last_name, profile.first_name, profile.id)
      from public.profiles profile
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', access_group.id, 'name', access_group.name, 'is_active', access_group.is_active
      ) order by access_group.name, access_group.id)
      from public.access_groups access_group
    ), '[]'::jsonb),
    'user_room_permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', permission.user_id, 'room_id', permission.room_id,
        'can_book', permission.can_book, 'can_repeat', permission.can_repeat
      ) order by permission.user_id, permission.room_id)
      from public.user_room_permissions permission
      where permission.can_book or permission.can_repeat
    ), '[]'::jsonb),
    'group_members', coalesce((
      select jsonb_agg(jsonb_build_object('group_id', member.group_id, 'user_id', member.user_id)
        order by member.group_id, member.user_id)
      from public.access_group_members member
    ), '[]'::jsonb),
    'group_room_permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'group_id', permission.group_id, 'room_id', permission.room_id,
        'can_book', permission.can_book, 'can_repeat', permission.can_repeat
      ) order by permission.group_id, permission.room_id)
      from public.access_group_rooms permission
      where permission.can_book or permission.can_repeat
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_room_access_overview() from public, anon;
grant execute on function public.admin_room_access_overview() to authenticated;

comment on function public.admin_room_access_overview() is
  'Aktív admin számára a helyiség- és hozzáférés-adminfelület biztonságos read-modelje.';

commit;
