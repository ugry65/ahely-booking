begin;

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Ez az archivált rekord nem módosítható és nem törölhető.' using errcode = '42501';
end;
$$;

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
  v_existing public.bookings%rowtype;
  v_booking_id uuid;
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

  -- Idempotent retries must be resolved before time-dependent validation: a
  -- previously successful request remains successful after its start time.
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

  perform public.assert_booking_request(
    v_actor_id, p_room_id, p_user_id, p_start_at, p_end_at, p_use_type
  );

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

revoke all on function public.create_booking(
  uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
) from public, anon;
grant execute on function public.create_booking(
  uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
) to authenticated;

comment on function public.create_booking(
  uuid, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid
) is
  'Tranzakciós, idempotens egyedi foglalás a create és update által közös assert_booking_request validációval.';

comment on column public.booking_cancellations.minutes_before_start is
  'A lemondás pillanata és a kezdés közti előjeles percek; admin utólagos lemondásánál szándékosan negatív lehet.';

commit;
