begin;

-- A publikus naptár-read model maradjon minimális. A szerkesztéshez szükséges
-- érzékenyebb metaadatokat külön RPC adja vissza, kizárólag saját foglalásra
-- vagy admin számára.
drop function if exists public.list_calendar_bookings(timestamptz,timestamptz);

create function public.list_calendar_bookings(
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  booking_id uuid,
  room_id uuid,
  room_name text,
  start_at timestamptz,
  end_at timestamptz,
  use_type public.booking_use_type,
  is_own boolean,
  booker_display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
begin
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode = '22023';
  end if;
  if p_end_at - p_start_at > interval '62 days' then
    raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode = '22023';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  return query
  select
    booking.id,
    room.id,
    room.name,
    booking.start_at,
    booking.end_at,
    booking.use_type,
    booking.user_id = v_actor.id,
    case
      when v_actor.role = 'admin'
        or booking.user_id = v_actor.id
        or v_actor.other_booker_names_visible
      then nullif(btrim(booker.last_name || ' ' || booker.first_name), '')
      else null
    end
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id and room.is_active
  join public.profiles booker on booker.id = booking.user_id
  where booking.status = 'active'
    and booking.start_at < p_end_at
    and booking.end_at > p_start_at
    and (
      v_actor.role = 'admin'
      or exists (
        select 1
        from public.effective_room_permissions(v_actor.id) permission
        where permission.room_id = room.id
          and permission.can_book
      )
    )
  order by booking.start_at, room.display_order, booking.id;
end;
$$;

create or replace function public.list_calendar_booking_management(
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  booking_id uuid,
  note text,
  series_id uuid,
  updated_at timestamptz,
  can_manage boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
begin
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode = '22023';
  end if;
  if p_end_at - p_start_at > interval '62 days' then
    raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode = '22023';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  return query
  select
    booking.id,
    booking.note,
    booking.series_id,
    booking.updated_at,
    true
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id and room.is_active
  where booking.status = 'active'
    and booking.start_at < p_end_at
    and booking.end_at > p_start_at
    and (v_actor.role = 'admin' or booking.user_id = v_actor.id)
  order by booking.start_at, booking.id;
end;
$$;

revoke execute on function public.list_calendar_bookings(timestamptz,timestamptz)
  from public, anon;
revoke execute on function public.list_calendar_booking_management(timestamptz,timestamptz)
  from public, anon;
grant execute on function public.list_calendar_bookings(timestamptz,timestamptz)
  to authenticated;
grant execute on function public.list_calendar_booking_management(timestamptz,timestamptz)
  to authenticated;

comment on function public.list_calendar_bookings(timestamptz,timestamptz) is
  'Minimális jogosultságszűrt naptár-read model; szerkesztési metaadatot nem szolgáltat.';
comment on function public.list_calendar_booking_management(timestamptz,timestamptz) is
  'Szerkesztési metaadat kizárólag saját foglalásokhoz vagy aktív admin számára.';

commit;
