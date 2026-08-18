begin;

create or replace function public.list_repeatable_rooms()
returns table (room_id uuid, room_name text, is_training_room boolean, display_order integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;
  return query
  select room.id, room.name, room.is_training_room, room.display_order
  from public.rooms room
  where room.is_active and (
    v_actor.role = 'admin' or (
      not room.is_training_room and exists (
        select 1 from public.effective_room_permissions(v_actor.id) permission
        where permission.room_id = room.id and permission.can_repeat
      )
    )
  )
  order by room.display_order, room.name, room.id;
end;
$$;

create or replace function public.get_my_booking_series_result(p_series_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor_id uuid := auth.uid();
begin
  if not exists (select 1 from public.profiles where id = v_actor_id and is_active) then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.booking_series series
    where series.id = p_series_id and series.owner_user_id = v_actor_id
  ) then
    raise exception 'A foglalási sorozat nem található.' using errcode = '42501';
  end if;
  return public.booking_series_result(p_series_id);
end;
$$;

revoke all on function public.list_repeatable_rooms() from public, anon;
grant execute on function public.list_repeatable_rooms() to authenticated;
revoke all on function public.get_my_booking_series_result(uuid) from public, anon;
grant execute on function public.get_my_booking_series_result(uuid) to authenticated;

comment on function public.list_repeatable_rooms() is
  'Az aktív user ismétlődő foglalásra jogosult aktív helyiségei; normál usernek a Tréningterem kizárt.';
comment on function public.get_my_booking_series_result(uuid) is
  'A bejelentkezett aktív user saját sorozatának létrehozott és kihagyott alkalmai.';

commit;
