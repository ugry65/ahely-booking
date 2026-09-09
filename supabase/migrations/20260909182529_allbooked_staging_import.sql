begin;

create table public.allbooked_migration_bookings (
  source_fingerprint text primary key,
  booking_id uuid not null unique references public.bookings(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  imported_by uuid not null references public.profiles(id) on delete restrict,
  source_system text not null default 'allbooked',
  imported_at timestamptz not null default clock_timestamp(),
  constraint allbooked_migration_fingerprint_format
    check (source_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint allbooked_migration_source_system
    check (source_system = 'allbooked')
);

alter table public.allbooked_migration_bookings enable row level security;
revoke all on table public.allbooked_migration_bookings from public, anon, authenticated, service_role;

create trigger allbooked_migration_bookings_immutable
before update or delete on public.allbooked_migration_bookings
for each row execute function public.prevent_audit_mutation();

create or replace function public.admin_reconcile_papp_dalma_allbooked(
  p_actor_id uuid,
  p_expected_fingerprints text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_room_id uuid;
  v_group_id uuid;
  v_result jsonb;
begin
  if not exists (
    select 1 from public.profiles
    where id = p_actor_id and role = 'admin' and is_active
  ) then
    raise exception 'Az import reconciliation csak aktív adminnal futtatható.' using errcode = '42501';
  end if;

  if coalesce(array_length(p_expected_fingerprints, 1), 0) <> 21
     or (select count(distinct fingerprint) from unnest(p_expected_fingerprints) fingerprint) <> 21
     or exists (select 1 from unnest(p_expected_fingerprints) fingerprint where fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Pontosan 21 egyedi, érvényes forrás-ujjlenyomat kötelező.' using errcode = '22023';
  end if;

  select id into v_user_id
  from public.profiles
  where email = 'pappdalma17@gmail.com';
  select id into v_room_id from public.rooms where name = 'Forrás tér' and is_active;
  select id into v_group_id from public.access_groups where name = 'Forrás tér' and is_active;

  if v_user_id is null or v_room_id is null or v_group_id is null then
    raise exception 'A migrált user, helyiség vagy hozzáférési csoport hiányzik.' using errcode = 'P0001';
  end if;

  select jsonb_build_object(
    'valid',
      (select count(*) = 1 from auth.users where id = v_user_id and lower(email) = 'pappdalma17@gmail.com')
      and (select count(*) = 1 from public.profiles where id = v_user_id and first_name = 'Dalma' and last_name = 'Papp' and email = 'pappdalma17@gmail.com' and phone = '+36307337981' and role = 'user' and is_active)
      and (select count(*) = 1 from public.access_group_members where user_id = v_user_id and group_id = v_group_id)
      and (select count(*) = 0 from public.access_group_members where user_id = v_user_id and group_id <> v_group_id)
      and (select count(*) = 1 from public.access_group_rooms where group_id = v_group_id and room_id = v_room_id and can_book and not can_repeat)
      and (select count(*) = 0 from public.user_room_permissions where user_id = v_user_id)
      and (select count(*) = 21 from public.allbooked_migration_bookings where user_id = v_user_id)
      and (select count(*) = 21 from public.allbooked_migration_bookings where user_id = v_user_id and source_fingerprint = any(p_expected_fingerprints))
      and (select count(*) = 21 from public.bookings where user_id = v_user_id)
      and (select count(*) = 21 from public.bookings where user_id = v_user_id and room_id = v_room_id and status = 'active' and use_type = 'individual' and series_id is null and note is null and booking_title is null)
      and (select count(*) = 19 from public.bookings where user_id = v_user_id and extract(epoch from (end_at - start_at)) / 60 = 60)
      and (select count(*) = 2 from public.bookings where user_id = v_user_id and extract(epoch from (end_at - start_at)) / 60 = 90)
      and (select coalesce(sum(extract(epoch from (end_at - start_at)) / 60), 0) = 1320 from public.bookings where user_id = v_user_id)
      and (select min((start_at at time zone 'Europe/Budapest')::date) = date '2026-09-03' and max((start_at at time zone 'Europe/Budapest')::date) = date '2026-09-17' from public.bookings where user_id = v_user_id)
      and (select count(*) = 0 from public.user_price_overrides where user_id = v_user_id)
      and (select count(*) = 0 from public.monthly_settlements where user_id = v_user_id)
      and (select count(*) = 0 from public.settlement_booking_lines line join public.bookings booking on booking.id = line.booking_id where booking.user_id = v_user_id)
      and (select count(*) = 0 from public.payments payment join public.monthly_settlements settlement on settlement.id = payment.settlement_id where settlement.user_id = v_user_id)
      and (select count(*) = 21 from public.audit_logs where action = 'allbooked.booking_imported' and entity_id in (select booking_id::text from public.allbooked_migration_bookings where user_id = v_user_id)),
    'userId', v_user_id,
    'email', 'pappdalma17@gmail.com',
    'phone', (select phone from public.profiles where id = v_user_id),
    'room', 'Forrás tér',
    'accessGroup', 'Forrás tér',
    'bookings', (select count(*) from public.bookings where user_id = v_user_id),
    'activeIndividualBookings', (select count(*) from public.bookings where user_id = v_user_id and room_id = v_room_id and status = 'active' and use_type = 'individual'),
    'migrationLedgerRows', (select count(*) from public.allbooked_migration_bookings where user_id = v_user_id),
    'duration60', (select count(*) from public.bookings where user_id = v_user_id and extract(epoch from (end_at - start_at)) / 60 = 60),
    'duration90', (select count(*) from public.bookings where user_id = v_user_id and extract(epoch from (end_at - start_at)) / 60 = 90),
    'totalMinutes', (select coalesce(sum(extract(epoch from (end_at - start_at)) / 60), 0)::integer from public.bookings where user_id = v_user_id),
    'firstServiceDate', (select min((start_at at time zone 'Europe/Budapest')::date) from public.bookings where user_id = v_user_id),
    'lastServiceDate', (select max((start_at at time zone 'Europe/Budapest')::date) from public.bookings where user_id = v_user_id),
    'directPermissions', (select count(*) from public.user_room_permissions where user_id = v_user_id),
    'legacyPriceOverrides', (select count(*) from public.user_price_overrides where user_id = v_user_id),
    'settlements', (select count(*) from public.monthly_settlements where user_id = v_user_id),
    'settlementLines', (select count(*) from public.settlement_booking_lines line join public.bookings booking on booking.id = line.booking_id where booking.user_id = v_user_id),
    'payments', (select count(*) from public.payments payment join public.monthly_settlements settlement on settlement.id = payment.settlement_id where settlement.user_id = v_user_id),
    'bookingImportAudits', (select count(*) from public.audit_logs where action = 'allbooked.booking_imported' and entity_id in (select booking_id::text from public.allbooked_migration_bookings where user_id = v_user_id))
  ) into v_result;

  if not coalesce((v_result ->> 'valid')::boolean, false) then
    raise exception 'Az AllBooked import reconciliation eltérést talált.' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.admin_import_papp_dalma_allbooked(
  p_actor_id uuid,
  p_user_id uuid,
  p_phone text,
  p_bookings jsonb,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_id uuid;
  v_group_id uuid;
  v_item jsonb;
  v_booking_id uuid;
  v_existing public.bookings%rowtype;
  v_created integer := 0;
  v_existing_count integer := 0;
  v_before jsonb;
  v_after jsonb;
  v_fingerprints text[];
  v_reconciliation jsonb;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin' and is_active) then
    raise exception 'Az importot csak aktív admin futtathatja.' using errcode = '42501';
  end if;
  if p_phone is distinct from '+36307337981' then
    raise exception 'A normalizált telefonszám eltér a jóváhagyott mintától.' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id and lower(email) = 'pappdalma17@gmail.com')
     or not exists (select 1 from public.profiles where id = p_user_id and email = 'pappdalma17@gmail.com' and role = 'user')
     or exists (select 1 from public.profiles where email = 'pappdalma17@gmail.com' and id <> p_user_id) then
    raise exception 'A célfelhasználó Auth/profile azonossága nem bizonyítható.' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_bookings) <> 'array' or jsonb_array_length(p_bookings) <> 21 then
    raise exception 'Pontosan 21 foglalás importálható.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_bookings) item
    where jsonb_typeof(item) <> 'object'
       or not item ?& array['sourceFingerprint','startAt','endAt','durationMinutes']
       or item - array['sourceFingerprint','startAt','endAt','durationMinutes'] <> '{}'::jsonb
  ) then
    raise exception 'A foglalási payload tiltott vagy hiányzó mezőt tartalmaz.' using errcode = '22023';
  end if;

  select array_agg(item ->> 'sourceFingerprint' order by item ->> 'sourceFingerprint')
  into v_fingerprints from jsonb_array_elements(p_bookings) item;
  if (select count(distinct fingerprint) from unnest(v_fingerprints) fingerprint) <> 21
     or exists (select 1 from unnest(v_fingerprints) fingerprint where fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'A forrás-ujjlenyomatok nem egyediek vagy hibásak.' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_bookings) item
    where (item ->> 'durationMinutes')::integer not in (60, 90)
       or (item ->> 'endAt')::timestamptz <= (item ->> 'startAt')::timestamptz
       or extract(epoch from ((item ->> 'endAt')::timestamptz - (item ->> 'startAt')::timestamptz)) / 60 <> (item ->> 'durationMinutes')::integer
       or ((item ->> 'startAt')::timestamptz at time zone 'Europe/Budapest')::date not between date '2026-09-03' and date '2026-09-17'
       or ((item ->> 'endAt')::timestamptz at time zone 'Europe/Budapest')::date <> ((item ->> 'startAt')::timestamptz at time zone 'Europe/Budapest')::date
  )
  or (select count(*) from jsonb_array_elements(p_bookings) item where (item ->> 'durationMinutes')::integer = 60) <> 19
  or (select count(*) from jsonb_array_elements(p_bookings) item where (item ->> 'durationMinutes')::integer = 90) <> 2
  or (select sum((item ->> 'durationMinutes')::integer) from jsonb_array_elements(p_bookings) item) <> 1320
  or (select min(((item ->> 'startAt')::timestamptz at time zone 'Europe/Budapest')::date) from jsonb_array_elements(p_bookings) item) <> date '2026-09-03'
  or (select max(((item ->> 'startAt')::timestamptz at time zone 'Europe/Budapest')::date) from jsonb_array_elements(p_bookings) item) <> date '2026-09-17' then
    raise exception 'A foglalási időpontok nem egyeznek a jóváhagyott 21/21 mintával.' using errcode = '22023';
  end if;

  select id into strict v_room_id from public.rooms where name = 'Forrás tér' and is_active;
  select id into strict v_group_id from public.access_groups where name = 'Forrás tér' and is_active;
  if not exists (select 1 from public.access_group_rooms where group_id = v_group_id and room_id = v_room_id and can_book and not can_repeat) then
    raise exception 'A Forrás tér csoportjog nincs a jóváhagyott állapotban.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('allbooked:pappdalma17@gmail.com', 0));
  if exists (select 1 from public.bookings booking where booking.user_id = p_user_id and not exists (select 1 from public.allbooked_migration_bookings ledger where ledger.booking_id = booking.id))
     or exists (select 1 from public.access_group_members where user_id = p_user_id and group_id <> v_group_id)
     or exists (select 1 from public.user_room_permissions where user_id = p_user_id)
     or exists (select 1 from public.user_price_overrides where user_id = p_user_id)
     or exists (select 1 from public.monthly_settlements where user_id = p_user_id) then
    raise exception 'A céluser meglévő üzleti adatai miatt az automatikus import lezárult.' using errcode = 'P0001';
  end if;

  select to_jsonb(profile) into v_before from public.profiles profile where id = p_user_id for update;
  update public.profiles
  set first_name = 'Dalma', last_name = 'Papp', phone = p_phone, is_active = true, updated_at = clock_timestamp()
  where id = p_user_id
    and (first_name is distinct from 'Dalma' or last_name is distinct from 'Papp' or phone is distinct from p_phone or not is_active);
  select to_jsonb(profile) into v_after from public.profiles profile where id = p_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (p_actor_id, 'allbooked.profile_imported', 'profile', p_user_id::text, v_before, v_after, p_correlation_id);
  end if;

  if not exists (select 1 from public.access_group_members where group_id = v_group_id and user_id = p_user_id) then
    insert into public.access_group_members(group_id, user_id) values (v_group_id, p_user_id);
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, after_data, correlation_id)
    values (p_actor_id, 'allbooked.access_imported', 'access_group_member', v_group_id::text || ':' || p_user_id::text,
      jsonb_build_object('group_id', v_group_id, 'user_id', p_user_id, 'source_tag', 'Forrás'), p_correlation_id);
  end if;

  for v_item in select item from jsonb_array_elements(p_bookings) item order by item ->> 'startAt' loop
    select booking.* into v_existing
    from public.allbooked_migration_bookings ledger
    join public.bookings booking on booking.id = ledger.booking_id
    where ledger.source_fingerprint = v_item ->> 'sourceFingerprint';

    if found then
      if v_existing.user_id <> p_user_id or v_existing.room_id <> v_room_id
         or v_existing.start_at <> (v_item ->> 'startAt')::timestamptz
         or v_existing.end_at <> (v_item ->> 'endAt')::timestamptz
         or v_existing.use_type <> 'individual' or v_existing.status <> 'active'
         or v_existing.series_id is not null or v_existing.note is not null or v_existing.booking_title is not null then
        raise exception 'Az idempotens újrafuttatás eltérő meglévő foglalást talált.' using errcode = 'P0001';
      end if;
      v_existing_count := v_existing_count + 1;
    else
      perform public.assert_booking_request(p_actor_id, v_room_id, p_user_id,
        (v_item ->> 'startAt')::timestamptz, (v_item ->> 'endAt')::timestamptz, 'individual');
      insert into public.bookings(room_id, user_id, created_by, start_at, end_at, use_type, status, note, booking_title, idempotency_key)
      values (v_room_id, p_user_id, p_actor_id, (v_item ->> 'startAt')::timestamptz, (v_item ->> 'endAt')::timestamptz,
        'individual', 'active', null, null, gen_random_uuid()) returning id into v_booking_id;
      insert into public.allbooked_migration_bookings(source_fingerprint, booking_id, user_id, imported_by)
      values (v_item ->> 'sourceFingerprint', v_booking_id, p_user_id, p_actor_id);
      insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, after_data, reason, correlation_id)
      values (p_actor_id, 'allbooked.booking_imported', 'booking', v_booking_id::text,
        jsonb_build_object('room_id', v_room_id, 'user_id', p_user_id, 'start_at', v_item ->> 'startAt',
          'end_at', v_item ->> 'endAt', 'duration_minutes', (v_item ->> 'durationMinutes')::integer,
          'use_type', 'individual', 'source_fingerprint', v_item ->> 'sourceFingerprint',
          'legacy_price_imported', false, 'legacy_payment_imported', false),
        'AllBooked staging migration #108/#124', p_correlation_id);
      v_created := v_created + 1;
    end if;
  end loop;

  v_reconciliation := public.admin_reconcile_papp_dalma_allbooked(p_actor_id, v_fingerprints);
  return v_reconciliation || jsonb_build_object('created', v_created, 'existing', v_existing_count);
end;
$$;

create or replace function public.admin_rollback_empty_papp_dalma_profile(
  p_actor_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin' and is_active) then
    raise exception 'A kompenzáló törlést csak aktív admin futtathatja.' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id and lower(email) = 'pappdalma17@gmail.com')
     or not exists (select 1 from public.profiles where id = p_user_id and email = 'pappdalma17@gmail.com') then
    raise exception 'A kompenzáló törlés célja nem azonosítható.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.bookings where user_id = p_user_id or created_by = p_user_id)
     or exists (select 1 from public.allbooked_migration_bookings where user_id = p_user_id or imported_by = p_user_id)
     or exists (select 1 from public.access_group_members where user_id = p_user_id)
     or exists (select 1 from public.user_room_permissions where user_id = p_user_id)
     or exists (select 1 from public.audit_logs where actor_user_id = p_user_id or entity_id = p_user_id::text) then
    raise exception 'A kompenzáló törlés nem biztonságos: kapcsolódó adat található.' using errcode = 'P0001';
  end if;
  delete from public.profiles where id = p_user_id;
  return found;
end;
$$;

revoke all on function public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.admin_reconcile_papp_dalma_allbooked(uuid,text[]) from public, anon, authenticated;
revoke all on function public.admin_rollback_empty_papp_dalma_profile(uuid,uuid) from public, anon, authenticated;
grant execute on function public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid) to service_role;
grant execute on function public.admin_reconcile_papp_dalma_allbooked(uuid,text[]) to service_role;
grant execute on function public.admin_rollback_empty_papp_dalma_profile(uuid,uuid) to service_role;

comment on table public.allbooked_migration_bookings is
  'Append-only AllBooked source fingerprint ledger; no legacy price or payment data is stored.';
comment on function public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid) is
  'Fail-closed, idempotent, atomic staging import for the approved Papp Dalma 21-booking sample. Service role only.';

commit;
