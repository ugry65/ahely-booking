begin;

create table public.booking_scope_operations (
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key uuid not null,
  action text not null check (action in ('update', 'cancel')),
  scope text not null check (scope in ('occurrence', 'following', 'series')),
  selected_booking_id uuid not null references public.bookings(id) on delete restrict,
  series_id uuid references public.booking_series(id) on delete restrict,
  request_payload jsonb not null,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, idempotency_key)
);

alter table public.booking_scope_operations enable row level security;
revoke all on table public.booking_scope_operations from public, anon, authenticated;

create trigger booking_scope_operations_no_physical_delete
before delete on public.booking_scope_operations
for each row execute function public.prevent_physical_delete();

-- A sorozatalkalmak táblája az eredeti generálás audit-pillanatképe marad.
-- A későbbi szerkesztések élő forrása a bookings tábla, a műveleti történetet
-- audit_logs + booking_scope_operations őrzi.

create or replace function public.update_booking_scope(
  p_booking_id uuid,
  p_scope text,
  p_expected_updated_at timestamptz,
  p_room_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.profiles%rowtype;
  v_booking public.bookings%rowtype;
  v_target public.bookings%rowtype;
  v_after public.bookings%rowtype;
  v_request jsonb;
  v_existing public.booking_scope_operations%rowtype;
  v_delta interval;
  v_duration interval;
  v_note text := nullif(trim(p_note), '');
  v_count integer := 0;
  v_lock bigint;
begin
  if v_actor_id is null then
    raise exception 'A módosításhoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;
  if p_booking_id is null or p_expected_updated_at is null or p_room_id is null
     or p_start_at is null or p_end_at is null or p_use_type is null or p_idempotency_key is null then
    raise exception 'A módosítás kötelező adatai hiányoznak.' using errcode = 'P0001';
  end if;
  if p_scope not in ('occurrence', 'following', 'series') then
    raise exception 'Érvénytelen szerkesztési hatókör.' using errcode = 'P0001';
  end if;

  select * into v_actor from public.profiles where id = v_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id;
  if not found or v_booking.status <> 'active' then
    raise exception 'Csak aktív foglalás módosítható.' using errcode = 'P0001';
  end if;
  if v_actor.role <> 'admin' and v_booking.user_id <> v_actor_id then
    raise exception 'Csak a saját foglalásodat módosíthatod.' using errcode = 'P0001';
  end if;
  if v_booking.updated_at <> p_expected_updated_at then
    raise exception 'A foglalás időközben módosult. Frissítsd az oldalt, majd próbáld újra.' using errcode = 'P0001';
  end if;
  if v_booking.series_id is null and p_scope <> 'occurrence' then
    raise exception 'Ez a foglalás nem ismétlődő sorozat része.' using errcode = 'P0001';
  end if;

  if v_booking.series_id is null then
    perform public.update_booking(
      p_booking_id, p_expected_updated_at, p_room_id, p_start_at, p_end_at,
      p_use_type, p_note, p_idempotency_key
    );
    return 1;
  end if;

  v_delta := p_start_at - v_booking.start_at;
  v_duration := p_end_at - p_start_at;
  if v_duration <= interval '0 seconds' then
    raise exception 'A befejezésnek a kezdés után kell lennie.' using errcode = 'P0001';
  end if;

  v_request := jsonb_build_object(
    'action', 'update', 'booking_id', p_booking_id, 'scope', p_scope,
    'expected_updated_at', p_expected_updated_at, 'room_id', p_room_id,
    'start_at', p_start_at, 'end_at', p_end_at, 'use_type', p_use_type,
    'note', v_note
  );

  begin
    insert into public.booking_scope_operations(
      actor_user_id, idempotency_key, action, scope, selected_booking_id,
      series_id, request_payload
    ) values (
      v_actor_id, p_idempotency_key, 'update', p_scope, p_booking_id,
      v_booking.series_id, v_request
    );
  exception when unique_violation then
    select * into v_existing from public.booking_scope_operations
    where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;
    if found and v_existing.request_payload = v_request and v_existing.result_payload is not null then
      return (v_existing.result_payload ->> 'affected_count')::integer;
    end if;
    raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode = 'P0001';
  end;

  -- Minden érintett jelenlegi és célhelyiség lockja determinisztikus sorrendben.
  for v_lock in
    select distinct lock_key from (
      select hashtextextended(b.room_id::text, 0) as lock_key
      from public.bookings b
      where b.series_id = v_booking.series_id and b.status = 'active'
        and b.start_at > clock_timestamp()
        and (p_scope = 'series'
          or (p_scope = 'following' and b.start_at >= v_booking.start_at)
          or (p_scope = 'occurrence' and b.id = p_booking_id))
      union all
      select hashtextextended(p_room_id::text, 0)
    ) locks order by lock_key
  loop
    perform pg_advisory_xact_lock(v_lock);
  end loop;

  -- Előbb minden célállapotot validálunk; hiba esetén semmi nem változik.
  for v_target in
    select * from public.bookings b
    where b.series_id = v_booking.series_id and b.status = 'active'
      and b.start_at > clock_timestamp()
      and (p_scope = 'series'
        or (p_scope = 'following' and b.start_at >= v_booking.start_at)
        or (p_scope = 'occurrence' and b.id = p_booking_id))
    order by b.start_at, b.id
  loop
    perform public.assert_booking_request(
      v_actor_id, p_room_id, v_target.user_id,
      v_target.start_at + v_delta,
      v_target.start_at + v_delta + v_duration,
      p_use_type
    );
  end loop;

  for v_target in
    select * from public.bookings b
    where b.series_id = v_booking.series_id and b.status = 'active'
      and b.start_at > clock_timestamp()
      and (p_scope = 'series'
        or (p_scope = 'following' and b.start_at >= v_booking.start_at)
        or (p_scope = 'occurrence' and b.id = p_booking_id))
    order by b.start_at, b.id
    for update
  loop
    begin
      update public.bookings
      set room_id = p_room_id,
          start_at = v_target.start_at + v_delta,
          end_at = v_target.start_at + v_delta + v_duration,
          use_type = p_use_type,
          note = v_note,
          updated_at = clock_timestamp()
      where id = v_target.id
      returning * into v_after;
    exception when exclusion_violation then
      raise exception 'A módosított sorozat egyik időpontja ütközik egy meglévő foglalással.' using errcode = 'P0001';
    end;

    insert into public.audit_logs(
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id, 'booking.updated', 'booking', v_target.id::text,
      to_jsonb(v_target), to_jsonb(v_after), p_idempotency_key
    );

    insert into public.outbox_events(event_type, aggregate_type, aggregate_id, payload)
    values ('booking.updated', 'booking', v_target.id::text,
      jsonb_build_object('booking_id', v_target.id, 'series_id', v_booking.series_id,
        'recipient_user_id', v_target.user_id, 'scope', p_scope));

    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception 'Nincs módosítható jövőbeli alkalom ebben a hatókörben.' using errcode = 'P0001';
  end if;

  update public.booking_scope_operations
  set result_payload = jsonb_build_object('affected_count', v_count)
  where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;

  insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, after_data, correlation_id)
  values (v_actor_id, 'booking_series.updated', 'booking_series', v_booking.series_id::text,
    jsonb_build_object('scope', p_scope, 'selected_booking_id', p_booking_id,
      'affected_count', v_count), p_idempotency_key);

  return v_count;
end;
$$;

create or replace function public.cancel_booking_scope(
  p_booking_id uuid,
  p_scope text,
  p_reason text,
  p_idempotency_key uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.profiles%rowtype;
  v_booking public.bookings%rowtype;
  v_target public.bookings%rowtype;
  v_request jsonb;
  v_existing public.booking_scope_operations%rowtype;
  v_reason text := nullif(trim(p_reason), '');
  v_cutoff_hours integer;
  v_minutes_before_start integer;
  v_count integer := 0;
begin
  if v_actor_id is null then
    raise exception 'A lemondáshoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;
  if p_booking_id is null or p_idempotency_key is null then
    raise exception 'A foglalás és a kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;
  if p_scope not in ('occurrence', 'following', 'series') then
    raise exception 'Érvénytelen törlési hatókör.' using errcode = 'P0001';
  end if;

  select * into v_actor from public.profiles where id = v_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;
  select * into v_booking from public.bookings where id = p_booking_id;
  if not found or v_booking.status <> 'active' then
    raise exception 'Csak aktív foglalás mondható le.' using errcode = 'P0001';
  end if;
  if v_actor.role <> 'admin' and v_booking.user_id <> v_actor_id then
    raise exception 'Csak a saját foglalásodat mondhatod le.' using errcode = 'P0001';
  end if;
  if v_booking.series_id is null and p_scope <> 'occurrence' then
    raise exception 'Ez a foglalás nem ismétlődő sorozat része.' using errcode = 'P0001';
  end if;

  if v_booking.series_id is null then
    perform public.cancel_booking(p_booking_id, p_reason, p_idempotency_key);
    return 1;
  end if;

  select (value #>> '{}')::integer into v_cutoff_hours
  from public.app_settings where key = 'cancellation_cutoff_hours';
  if v_cutoff_hours is null or v_cutoff_hours < 0 then
    raise exception 'A lemondási határidő beállítása hiányzik vagy hibás.' using errcode = 'P0001';
  end if;

  v_request := jsonb_build_object(
    'action', 'cancel', 'booking_id', p_booking_id, 'scope', p_scope, 'reason', v_reason
  );
  begin
    insert into public.booking_scope_operations(
      actor_user_id, idempotency_key, action, scope, selected_booking_id,
      series_id, request_payload
    ) values (
      v_actor_id, p_idempotency_key, 'cancel', p_scope, p_booking_id,
      v_booking.series_id, v_request
    );
  exception when unique_violation then
    select * into v_existing from public.booking_scope_operations
    where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;
    if found and v_existing.request_payload = v_request and v_existing.result_payload is not null then
      return (v_existing.result_payload ->> 'affected_count')::integer;
    end if;
    raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode = 'P0001';
  end;

  -- A teljes hatókört validáljuk a módosítás előtt, így a művelet atomi.
  for v_target in
    select * from public.bookings b
    where b.series_id = v_booking.series_id and b.status = 'active'
      and b.start_at > clock_timestamp()
      and (p_scope = 'series'
        or (p_scope = 'following' and b.start_at >= v_booking.start_at)
        or (p_scope = 'occurrence' and b.id = p_booking_id))
    order by b.start_at, b.id
  loop
    if v_actor.role <> 'admin'
       and clock_timestamp() > v_target.start_at - make_interval(hours => v_cutoff_hours) then
      raise exception 'A sorozat egyik érintett foglalása % órán belül kezdődik, ezért a művelet nem hajtható végre.',
        v_cutoff_hours using errcode = 'P0001';
    end if;
  end loop;

  for v_target in
    select * from public.bookings b
    where b.series_id = v_booking.series_id and b.status = 'active'
      and b.start_at > clock_timestamp()
      and (p_scope = 'series'
        or (p_scope = 'following' and b.start_at >= v_booking.start_at)
        or (p_scope = 'occurrence' and b.id = p_booking_id))
    order by b.start_at, b.id
    for update
  loop
    v_minutes_before_start := floor(extract(epoch from (v_target.start_at - clock_timestamp())) / 60)::integer;

    update public.bookings set status = 'cancelled', updated_at = clock_timestamp()
    where id = v_target.id;

    insert into public.booking_cancellations(
      booking_id, cancelled_by, minutes_before_start, reason,
      original_snapshot, idempotency_key, settlement_excluded
    ) values (
      v_target.id, v_actor_id, v_minutes_before_start, v_reason,
      to_jsonb(v_target), gen_random_uuid(), true
    );

    insert into public.audit_logs(
      actor_user_id, action, entity_type, entity_id, before_data, after_data,
      reason, correlation_id
    ) values (
      v_actor_id, 'booking.cancelled', 'booking', v_target.id::text,
      to_jsonb(v_target), jsonb_build_object('status', 'cancelled', 'settlement_excluded', true),
      v_reason, p_idempotency_key
    );

    insert into public.outbox_events(event_type, aggregate_type, aggregate_id, payload)
    values ('booking.cancelled', 'booking', v_target.id::text,
      jsonb_build_object('booking_id', v_target.id, 'series_id', v_booking.series_id,
        'recipient_user_id', v_target.user_id, 'settlement_excluded', true, 'scope', p_scope));

    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception 'Nincs lemondható jövőbeli alkalom ebben a hatókörben.' using errcode = 'P0001';
  end if;

  update public.booking_scope_operations
  set result_payload = jsonb_build_object('affected_count', v_count)
  where actor_user_id = v_actor_id and idempotency_key = p_idempotency_key;

  insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, after_data, reason, correlation_id)
  values (v_actor_id, 'booking_series.cancelled', 'booking_series', v_booking.series_id::text,
    jsonb_build_object('scope', p_scope, 'selected_booking_id', p_booking_id,
      'affected_count', v_count), v_reason, p_idempotency_key);

  return v_count;
end;
$$;

revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)
  from public, anon;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)
  to authenticated;
revoke all on function public.cancel_booking_scope(uuid,text,text,uuid) from public, anon;
grant execute on function public.cancel_booking_scope(uuid,text,text,uuid) to authenticated;

comment on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) is
  'Naptárból indított foglalásszerkesztés. Sorozatnál occurrence/following/series hatókört támogat; csak jövőbeli aktív alkalmak változnak, auditálva és atomikusan.';
comment on function public.cancel_booking_scope(uuid,text,text,uuid) is
  'Naptárból indított lemondás. Sorozatnál occurrence/following/series hatókört támogat; csak jövőbeli aktív alkalmak mondódnak le, normál user cutoff szabályával.';

-- A naptár read model a kezelési UI-hoz szükséges adatokat csak annak adja ki,
-- aki az adott foglalást kezelheti (saját foglalás vagy admin).
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
  booker_display_name text,
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

  select * into v_actor from public.profiles where id = auth.uid() and is_active;
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
      when v_actor.role = 'admin' or booking.user_id = v_actor.id or v_actor.other_booker_names_visible
      then nullif(btrim(booker.last_name || ' ' || booker.first_name), '')
      else null
    end,
    case when v_actor.role = 'admin' or booking.user_id = v_actor.id then booking.note else null end,
    case when v_actor.role = 'admin' or booking.user_id = v_actor.id then booking.series_id else null end,
    case when v_actor.role = 'admin' or booking.user_id = v_actor.id then booking.updated_at else null end,
    (v_actor.role = 'admin' or booking.user_id = v_actor.id)
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id and room.is_active
  join public.profiles booker on booker.id = booking.user_id
  where booking.status = 'active'
    and booking.start_at < p_end_at
    and booking.end_at > p_start_at
    and (
      v_actor.role = 'admin'
      or exists (
        select 1 from public.effective_room_permissions(v_actor.id) permission
        where permission.room_id = room.id and permission.can_book
      )
    )
  order by booking.start_at, room.display_order, booking.id;
end;
$$;

revoke all on function public.list_calendar_bookings(timestamptz,timestamptz) from public, anon;
grant execute on function public.list_calendar_bookings(timestamptz,timestamptz) to authenticated;

comment on function public.list_calendar_bookings(timestamptz,timestamptz) is
  'Jogosultságszűrt naptár-read model. Saját/admin foglalásnál kezelési metaadatokat is ad a szerkesztés/duplikálás/törlés UI-hoz.';

commit;
