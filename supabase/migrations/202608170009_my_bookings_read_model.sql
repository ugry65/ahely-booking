begin;

create or replace function public.list_my_bookings()
returns table (
  booking_id uuid,
  room_id uuid,
  room_name text,
  start_at timestamptz,
  end_at timestamptz,
  use_type public.booking_use_type,
  note text,
  series_id uuid,
  updated_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  return query
  select booking.id, room.id, room.name, booking.start_at, booking.end_at,
    booking.use_type, booking.note, booking.series_id, booking.updated_at
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id
  where booking.user_id = v_actor.id
    and booking.status = 'active'
    and booking.end_at > now()
  order by booking.start_at, room.display_order, booking.id;
end;
$$;

revoke all on function public.list_my_bookings() from public, anon;
grant execute on function public.list_my_bookings() to authenticated;
comment on function public.list_my_bookings() is
  'Az aktív felhasználó saját, még le nem zárult aktív foglalásai a Foglalásaim felülethez.';

commit;
