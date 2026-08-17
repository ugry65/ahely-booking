begin;

alter function public.validate_booking_time_rules() security definer;

create table public.booking_operation_requests (
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key uuid not null,
  operation text not null check (operation in ('update', 'cancel')),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  request_payload jsonb not null,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, idempotency_key)
);

alter table public.booking_operation_requests enable row level security;

create trigger booking_operation_requests_no_physical_delete
before delete on public.booking_operation_requests
for each row execute function public.prevent_physical_delete();

alter table public.booking_cancellations
  add column idempotency_key uuid,
  add column settlement_excluded boolean not null default true,
  add constraint booking_cancellations_settlement_excluded check (settlement_excluded);

update public.booking_cancellations
set idempotency_key = gen_random_uuid()
where idempotency_key is null;

alter table public.booking_cancellations
  alter column idempotency_key set not null,
  add constraint booking_cancellations_actor_idempotency_unique
    unique (cancelled_by, idempotency_key);

create trigger booking_cancellations_immutable
before update or delete on public.booking_cancellations
for each row execute function public.prevent_audit_mutation();

create or replace function public.cancel_booking(
  p_booking_id uuid,
  p_reason text,
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
  v_booking public.bookings%rowtype;
  v_request_payload jsonb;
  v_existing_request public.booking_operation_requests%rowtype;
  v_cutoff_hours integer;
  v_minutes_before_start integer;
  v_reason text := nullif(trim(p_reason), '');
begin
  if v_actor_id is null then
    raise exception 'A lemondáshoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;

  select * into v_actor
  from public.profiles
  where id = v_actor_id;

  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_booking_id is null or p_idempotency_key is null then
    raise exception 'A foglalás és a kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;

  v_request_payload := jsonb_build_object(
    'operation', 'cancel',
    'booking_id', p_booking_id,
    'reason', v_reason
  );

  perform 1 from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'A foglalás nem található.' using errcode = 'P0001';
  end if;

  begin
    insert into public.booking_operation_requests (
      actor_user_id, idempotency_key, operation, booking_id, request_payload
    ) values (
      v_actor_id, p_idempotency_key, 'cancel', p_booking_id, v_request_payload
    );
  exception
    when unique_violation then
      select * into v_existing_request
      from public.booking_operation_requests
      where actor_user_id = v_actor_id
        and idempotency_key = p_idempotency_key;

      if found
        and v_existing_request.operation = 'cancel'
        and v_existing_request.booking_id = p_booking_id
        and v_existing_request.request_payload = v_request_payload
        and v_existing_request.result_payload is not null
      then
        return (v_existing_request.result_payload ->> 'booking_id')::uuid;
      end if;

      raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode = 'P0001';
  end;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.status <> 'active' then
    raise exception 'A foglalás már le van mondva.' using errcode = 'P0001';
  end if;

  if v_actor.role <> 'admin' and v_booking.user_id <> v_actor_id then
    raise exception 'Csak a saját foglalásodat mondhatod le.' using errcode = 'P0001';
  end if;

  select (value #>> '{}')::integer into v_cutoff_hours
  from public.app_settings
  where key = 'cancellation_cutoff_hours';

  if v_cutoff_hours is null or v_cutoff_hours < 0 then
    raise exception 'A lemondási határidő beállítása hiányzik vagy hibás.' using errcode = 'P0001';
  end if;

  if v_actor.role <> 'admin'
    and clock_timestamp() > v_booking.start_at - make_interval(hours => v_cutoff_hours)
  then
    raise exception 'A foglalás % órán belül már nem mondható le.', v_cutoff_hours using errcode = 'P0001';
  end if;

  v_minutes_before_start := floor(extract(epoch from (v_booking.start_at - clock_timestamp())) / 60)::integer;

  update public.bookings
  set status = 'cancelled', updated_at = clock_timestamp()
  where id = p_booking_id;

  insert into public.booking_cancellations (
    booking_id,
    cancelled_by,
    minutes_before_start,
    reason,
    original_snapshot,
    idempotency_key,
    settlement_excluded
  ) values (
    p_booking_id,
    v_actor_id,
    v_minutes_before_start,
    v_reason,
    to_jsonb(v_booking),
    p_idempotency_key,
    true
  );

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason,
    correlation_id
  ) values (
    v_actor_id,
    'booking.cancelled',
    'booking',
    p_booking_id::text,
    to_jsonb(v_booking),
    jsonb_build_object('status', 'cancelled', 'settlement_excluded', true),
    v_reason,
    p_idempotency_key
  );

  insert into public.outbox_events (
    event_type, aggregate_type, aggregate_id, payload
  ) values (
    'booking.cancelled',
    'booking',
    p_booking_id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'recipient_user_id', v_booking.user_id,
      'settlement_excluded', true
    )
  );

  update public.booking_operation_requests
  set result_payload = jsonb_build_object(
    'booking_id', p_booking_id,
    'status', 'cancelled',
    'settlement_excluded', true
  )
  where actor_user_id = v_actor_id
    and idempotency_key = p_idempotency_key;

  return p_booking_id;
end;
$$;

create or replace function public.assert_booking_request(
  p_actor_id uuid,
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_room public.rooms%rowtype;
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
begin
  select * into v_actor from public.profiles where id = p_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_room_id is null or p_user_id is null or p_start_at is null or p_end_at is null or p_use_type is null then
    raise exception 'A foglalás kötelező adatai hiányoznak.' using errcode = 'P0001';
  end if;

  if not isfinite(p_start_at) or not isfinite(p_end_at) then
    raise exception 'A foglalás időpontja nem érvényes.' using errcode = 'P0001';
  end if;

  v_is_admin := v_actor.role = 'admin';

  select * into v_target from public.profiles where id = p_user_id;
  if not found or not v_target.is_active then
    raise exception 'A foglalás célfelhasználója nem aktív.' using errcode = 'P0001';
  end if;

  if not v_is_admin and p_user_id <> p_actor_id then
    raise exception 'Más felhasználó nevében csak admin járhat el.' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found or not v_room.is_active then
    raise exception 'A kiválasztott helyiség nem foglalható.' using errcode = 'P0001';
  end if;

  if not v_is_admin and not (
    exists (
      select 1 from public.user_room_permissions
      where user_id = p_user_id and room_id = p_room_id and can_book
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

  v_duration_minutes := extract(epoch from (p_end_at - p_start_at))::bigint / 60;
  v_start_local := p_start_at at time zone v_timezone;
  v_end_local := p_end_at at time zone v_timezone;
  v_service_date := v_start_local::date;

  if v_start_local::date <> v_end_local::date then
    raise exception 'A foglalás nem nyúlhat át másik napra.' using errcode = 'P0001';
  end if;

  if v_duration_minutes < v_minimum_minutes then
    raise exception 'A foglalás legalább % perces legyen.', v_minimum_minutes using errcode = 'P0001';
  end if;

  -- A helyi faliidő-rács biztonságos, amíg a nyitvatartás nem érinti a
  -- DST-visszaállás ismétlődő 02:00–03:00 óráját.
  if v_duration_minutes % v_slot_minutes <> 0
    or extract(epoch from v_start_local::time)::bigint % (v_slot_minutes * 60) <> 0
    or extract(epoch from v_end_local::time)::bigint % (v_slot_minutes * 60) <> 0
  then
    raise exception 'A kezdésnek, befejezésnek és időtartamnak % perces rácshoz kell igazodnia.',
      v_slot_minutes using errcode = 'P0001';
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
end;
$$;

create or replace function public.update_booking(
  p_booking_id uuid,
  p_expected_updated_at timestamptz,
  p_room_id uuid,
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
  v_booking public.bookings%rowtype;
  v_after public.bookings%rowtype;
  v_request_payload jsonb;
  v_existing_request public.booking_operation_requests%rowtype;
  v_note text := nullif(trim(p_note), '');
begin
  if v_actor_id is null then
    raise exception 'A módosításhoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;

  select * into v_actor from public.profiles where id = v_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_booking_id is null or p_expected_updated_at is null or p_idempotency_key is null then
    raise exception 'A foglalás, a verzió és a kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;

  perform 1 from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'A foglalás nem található.' using errcode = 'P0001';
  end if;

  v_request_payload := jsonb_build_object(
    'operation', 'update',
    'booking_id', p_booking_id,
    'expected_updated_at', p_expected_updated_at,
    'room_id', p_room_id,
    'start_at', p_start_at,
    'end_at', p_end_at,
    'use_type', p_use_type,
    'note', v_note
  );

  begin
    insert into public.booking_operation_requests (
      actor_user_id, idempotency_key, operation, booking_id, request_payload
    ) values (
      v_actor_id, p_idempotency_key, 'update', p_booking_id, v_request_payload
    );
  exception
    when unique_violation then
      select * into v_existing_request
      from public.booking_operation_requests
      where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;

      if found
        and v_existing_request.operation = 'update'
        and v_existing_request.booking_id = p_booking_id
        and v_existing_request.request_payload = v_request_payload
        and v_existing_request.result_payload is not null
      then
        return (v_existing_request.result_payload ->> 'booking_id')::uuid;
      end if;

      raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode = 'P0001';
  end;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.status <> 'active' then
    raise exception 'Csak aktív foglalás módosítható.' using errcode = 'P0001';
  end if;

  if v_booking.series_id is not null then
    raise exception 'Ismétlődő sorozat alkalmát a sorozatkezelőben lehet módosítani.' using errcode = 'P0001';
  end if;

  if v_actor.role <> 'admin' and v_booking.user_id <> v_actor_id then
    raise exception 'Csak a saját foglalásodat módosíthatod.' using errcode = 'P0001';
  end if;

  if v_booking.updated_at <> p_expected_updated_at then
    raise exception 'A foglalás időközben módosult. Frissítsd az oldalt, majd próbáld újra.' using errcode = 'P0001';
  end if;

  perform public.assert_booking_request(
    v_actor_id, p_room_id, v_booking.user_id, p_start_at, p_end_at, p_use_type
  );

  begin
    update public.bookings
    set room_id = p_room_id,
        start_at = p_start_at,
        end_at = p_end_at,
        use_type = p_use_type,
        note = v_note,
        updated_at = clock_timestamp()
    where id = p_booking_id
    returning * into v_after;
  exception
    when exclusion_violation then
      raise exception 'A helyiség a kiválasztott időpontban már foglalt.' using errcode = 'P0001';
  end;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id,
    before_data, after_data, correlation_id
  ) values (
    v_actor_id, 'booking.updated', 'booking', p_booking_id::text,
    to_jsonb(v_booking), to_jsonb(v_after), p_idempotency_key
  );

  insert into public.outbox_events (
    event_type, aggregate_type, aggregate_id, payload
  ) values (
    'booking.updated', 'booking', p_booking_id::text,
    jsonb_build_object('booking_id', p_booking_id, 'recipient_user_id', v_booking.user_id)
  );

  update public.booking_operation_requests
  set result_payload = jsonb_build_object(
    'booking_id', p_booking_id,
    'updated_at', v_after.updated_at
  )
  where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;

  return p_booking_id;
end;
$$;

revoke all on table public.booking_operation_requests from public, anon, authenticated;
revoke all on function public.assert_booking_request(uuid, uuid, uuid, timestamptz, timestamptz, public.booking_use_type)
from public, anon, authenticated;
revoke all on function public.cancel_booking(uuid, text, uuid) from public, anon;
revoke all on function public.update_booking(uuid, timestamptz, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid)
from public, anon;
grant execute on function public.cancel_booking(uuid, text, uuid) to authenticated;
grant execute on function public.update_booking(uuid, timestamptz, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid)
to authenticated;

comment on table public.booking_operation_requests is
  'Foglalásmódosítási és lemondási műveletek tranzakciós idempotencia-ledgere.';
comment on column public.booking_cancellations.settlement_excluded is
  'Jóváhagyott üzleti döntés: minden szabályosan lemondott foglalás 0 Ft és kimarad az elszámolásból.';
comment on function public.cancel_booking(uuid, text, uuid) is
  'Történetmegőrző, auditált, idempotens lemondás 24 órás user-határidővel és admin felülbírálással.';
comment on function public.assert_booking_request(uuid, uuid, uuid, timestamptz, timestamptz, public.booking_use_type) is
  'Belső, közös módosítási validátor a teljes helyiségjog-, időablak- és speciális szabálykészlethez.';
comment on function public.update_booking(uuid, timestamptz, uuid, timestamptz, timestamptz, public.booking_use_type, text, uuid) is
  'Tranzakciós, idempotens egyedi foglalásmódosítás teljes újraellenőrzéssel és optimista verzióvédelemmel.';

commit;
