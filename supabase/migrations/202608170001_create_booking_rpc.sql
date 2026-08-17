begin;

create or replace function public.create_booking(
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_existing public.bookings%rowtype;
  v_booking_id uuid;
  v_is_admin boolean;
  v_timezone text;
  v_slot_minutes integer;
  v_minimum_minutes integer;
  v_advance_days integer;
  v_training_advance_days integer;
  v_duration_minutes bigint;
  v_start_local timestamp;
  v_end_local timestamp;
  v_service_date date;
  v_opens_at time;
  v_closes_at time;
  v_is_closed boolean;
  v_has_exception boolean;
  v_normalized_note text := nullif(trim(p_note), '');
begin
  if v_actor_id is null then
    raise exception 'A foglaláshoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;

  select * into v_actor
  from public.profiles
  where id = v_actor_id;

  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_idempotency_key is null then
    raise exception 'A kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;

  select * into v_existing
  from public.bookings
  where created_by = v_actor_id
    and idempotency_key = p_idempotency_key;

  if found then
    if v_existing.room_id = p_room_id
      and v_existing.user_id = p_user_id
      and v_existing.start_at = p_start_at
      and v_existing.end_at = p_end_at
      and v_existing.use_type = p_use_type
      and v_existing.note is not distinct from v_normalized_note
    then
      return v_existing.id;
    end if;

    raise exception 'Ezt a kérésazonosítót már más foglalási adatokkal használták.' using errcode = 'P0001';
  end if;

  if p_room_id is null or p_user_id is null or p_start_at is null or p_end_at is null or p_use_type is null then
    raise exception 'A foglalás kötelező adatai hiányoznak.' using errcode = 'P0001';
  end if;

  if not isfinite(p_start_at) or not isfinite(p_end_at) then
    raise exception 'A foglalás időpontja nem érvényes.' using errcode = 'P0001';
  end if;

  v_is_admin := v_actor.role = 'admin';

  select * into v_target
  from public.profiles
  where id = p_user_id;

  if not found or not v_target.is_active then
    raise exception 'A foglalás célfelhasználója nem aktív.' using errcode = 'P0001';
  end if;

  if not v_is_admin and p_user_id <> v_actor_id then
    raise exception 'Más felhasználó nevében csak admin foglalhat.' using errcode = 'P0001';
  end if;

  select * into v_room
  from public.rooms
  where id = p_room_id;

  if not found or not v_room.is_active then
    raise exception 'A kiválasztott helyiség nem foglalható.' using errcode = 'P0001';
  end if;

  if not v_is_admin and not (
    exists (
      select 1
      from public.user_room_permissions
      where user_id = p_user_id
        and room_id = p_room_id
        and can_book
    )
    or exists (
      select 1
      from public.access_group_members membership
      join public.access_groups access_group on access_group.id = membership.group_id
      join public.access_group_rooms group_room on group_room.group_id = membership.group_id
      where membership.user_id = p_user_id
        and access_group.is_active
        and group_room.room_id = p_room_id
        and group_room.can_book
    )
  ) then
    raise exception 'Nincs foglalási jogosultságod ehhez a helyiséghez.' using errcode = 'P0001';
  end if;

  select value #>> '{}' into v_timezone from public.app_settings where key = 'timezone';
  select (value #>> '{}')::integer into v_slot_minutes from public.app_settings where key = 'slot_minutes';
  select (value #>> '{}')::integer into v_minimum_minutes from public.app_settings where key = 'minimum_booking_minutes';
  select (value #>> '{}')::integer into v_advance_days from public.app_settings where key = 'default_advance_booking_days';
  select (value #>> '{}')::integer into v_training_advance_days from public.app_settings where key = 'training_room_advance_days';

  if v_timezone is null or v_slot_minutes is null or v_slot_minutes <= 0
    or v_minimum_minutes is null or v_minimum_minutes <= 0
    or v_advance_days is null or v_advance_days < 0
    or v_training_advance_days is null or v_training_advance_days < 0
  then
    raise exception 'A foglalási beállítások hiányosak vagy hibásak.' using errcode = 'P0001';
  end if;

  if p_end_at <= p_start_at then
    raise exception 'A befejezésnek a kezdés után kell lennie.' using errcode = 'P0001';
  end if;

  v_duration_minutes := extract(epoch from (p_end_at - p_start_at))::integer / 60;
  v_start_local := p_start_at at time zone v_timezone;
  v_end_local := p_end_at at time zone v_timezone;
  v_service_date := v_start_local::date;

  if v_start_local::date <> v_end_local::date then
    raise exception 'A foglalás nem nyúlhat át másik napra.' using errcode = 'P0001';
  end if;

  if v_duration_minutes < v_minimum_minutes then
    raise exception 'A foglalás legalább % perces legyen.', v_minimum_minutes using errcode = 'P0001';
  end if;

  if v_duration_minutes % v_slot_minutes <> 0
    or extract(epoch from v_start_local::time)::bigint % (v_slot_minutes * 60) <> 0
    or extract(epoch from v_end_local::time)::bigint % (v_slot_minutes * 60) <> 0
  then
    raise exception 'A kezdésnek, befejezésnek és időtartamnak % perces rácshoz kell igazodnia.', v_slot_minutes using errcode = 'P0001';
  end if;

  if p_start_at <= clock_timestamp() then
    raise exception 'Csak jövőbeli időpontra lehet foglalni.' using errcode = 'P0001';
  end if;

  if not v_is_admin then
    v_advance_days := coalesce(v_target.advance_booking_days_override, v_advance_days);

    if v_room.is_training_room then
      v_advance_days := least(v_advance_days, v_training_advance_days);
    end if;

    if v_service_date > (clock_timestamp() at time zone v_timezone)::date + v_advance_days then
      if v_room.is_training_room then
        raise exception 'A Tréningterem legfeljebb % napra előre foglalható.', v_advance_days using errcode = 'P0001';
      end if;

      raise exception 'Legfeljebb % napra előre foglalhatsz.', v_advance_days using errcode = 'P0001';
    end if;
  end if;

  if not v_room.is_training_room and p_use_type = 'group' then
    raise exception 'Csoportos használattípus csak a Tréningteremnél választható.' using errcode = 'P0001';
  end if;

  select opens_at, closes_at, is_closed
  into v_opens_at, v_closes_at, v_is_closed
  from public.calendar_exceptions
  where service_date = v_service_date;
  v_has_exception := found;

  if not v_has_exception then
    select opens_at, closes_at, is_closed
    into v_opens_at, v_closes_at, v_is_closed
    from public.weekly_opening_hours
    where iso_weekday = extract(isodow from v_start_local)::integer;

    if not found then
      raise exception 'Erre a napra nincs nyitvatartás beállítva.' using errcode = 'P0001';
    end if;
  end if;

  if v_is_closed then
    raise exception 'A kiválasztott napon az A-Hely zárva tart.' using errcode = 'P0001';
  end if;

  if v_start_local::time < v_opens_at or v_end_local::time > v_closes_at then
    raise exception 'A foglalásnak a %–% közötti nyitvatartásba kell esnie.',
      to_char(v_opens_at, 'HH24:MI'), to_char(v_closes_at, 'HH24:MI') using errcode = 'P0001';
  end if;

  begin
    insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, use_type, note, idempotency_key
    ) values (
      p_room_id, p_user_id, v_actor_id, p_start_at, p_end_at, p_use_type,
      v_normalized_note, p_idempotency_key
    )
    returning id into v_booking_id;
  exception
    when exclusion_violation then
      raise exception 'A helyiség a kiválasztott időpontban már foglalt.' using errcode = 'P0001';
    when unique_violation then
      select * into v_existing
      from public.bookings
      where created_by = v_actor_id
        and idempotency_key = p_idempotency_key;

      if found
        and v_existing.room_id = p_room_id
        and v_existing.user_id = p_user_id
        and v_existing.start_at = p_start_at
        and v_existing.end_at = p_end_at
        and v_existing.use_type = p_use_type
        and v_existing.note is not distinct from v_normalized_note
      then
        return v_existing.id;
      end if;

      raise exception 'Ezt a kérésazonosítót már más foglalási adatokkal használták.' using errcode = 'P0001';
  end;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, after_data, correlation_id
  ) values (
    v_actor_id,
    'booking.created',
    'booking',
    v_booking_id::text,
    jsonb_build_object(
      'room_id', p_room_id,
      'user_id', p_user_id,
      'start_at', p_start_at,
      'end_at', p_end_at,
      'use_type', p_use_type
    ),
    p_idempotency_key
  );

  insert into public.outbox_events (
    event_type, aggregate_type, aggregate_id, payload
  ) values (
    'booking.created',
    'booking',
    v_booking_id::text,
    jsonb_build_object('booking_id', v_booking_id, 'recipient_user_id', p_user_id)
  );

  return v_booking_id;
end;
$$;

revoke all on function public.create_booking(uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid)
from public, anon;

grant execute on function public.create_booking(uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid)
to authenticated;

comment on function public.create_booking(uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid) is
  'Tranzakciós, idempotens egyedi foglalás actor-, jogosultság-, időablak- és ütközésellenőrzéssel; audit- és outbox-mellékhatással.';

commit;
