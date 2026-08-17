begin;

create or replace function public.list_bookable_rooms()
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
    v_actor.role = 'admin' or exists (
      select 1 from public.effective_room_permissions(v_actor.id) permission
      where permission.room_id = room.id and permission.can_book
    )
  )
  order by room.display_order, room.name, room.id;
end;
$$;

revoke all on function public.list_bookable_rooms() from public, anon;
grant execute on function public.list_bookable_rooms() to authenticated;
comment on function public.list_bookable_rooms() is
  'Aktív user jogosultságszűrt helyiséglistája a foglalási UI-hoz; admin minden aktív helyiséget lát.';

commit;
