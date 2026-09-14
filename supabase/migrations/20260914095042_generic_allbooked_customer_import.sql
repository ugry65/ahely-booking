alter type public.booking_status add value if not exists 'voided';

begin;

create or replace function public.admin_import_allbooked_customer(
  p_actor_id uuid,
  p_user_id uuid,
  p_email text,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_access_group_names text[],
  p_bookings jsonb,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_expected_groups text[];
  v_item jsonb;
  v_room public.rooms%rowtype;
  v_existing public.bookings%rowtype;
  v_booking_id uuid;
  v_group_id uuid;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_created integer := 0;
  v_existing_count integer := 0;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin' and is_active) then
    raise exception 'Az importot csak aktív admin futtathatja.' using errcode = '42501';
  end if;
  if v_email = '' or p_email is distinct from v_email
     or nullif(trim(p_first_name), '') is null or nullif(trim(p_last_name), '') is null
     or length(trim(p_first_name)) > 100 or length(trim(p_last_name)) > 100
     or (p_phone is not null and length(p_phone) > 50) then
    raise exception 'A normalizált ügyféladatok hibásak.' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id and lower(email) = v_email)
     or not exists (select 1 from public.profiles where id = p_user_id and email = v_email and role = 'user')
     or exists (select 1 from public.profiles where email = v_email and id <> p_user_id) then
    raise exception 'A célfelhasználó Auth/profile azonossága nem bizonyítható.' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_bookings) <> 'array' or jsonb_array_length(p_bookings) not between 1 and 2000 then
    raise exception 'Egy import 1 és 2000 közötti foglalást tartalmazhat.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_bookings) item
    where jsonb_typeof(item) <> 'object'
       or not item ?& array['sourceFingerprint','roomName','startLocal','endLocal','durationMinutes','bookingTitle','useType']
       or item - array['sourceFingerprint','roomName','startLocal','endLocal','durationMinutes','bookingTitle','useType'] <> '{}'::jsonb
       or jsonb_typeof(item -> 'sourceFingerprint') <> 'string'
       or jsonb_typeof(item -> 'roomName') <> 'string'
       or jsonb_typeof(item -> 'startLocal') <> 'string'
       or jsonb_typeof(item -> 'endLocal') <> 'string'
       or jsonb_typeof(item -> 'durationMinutes') <> 'number'
       or jsonb_typeof(item -> 'useType') <> 'string'
       or item ->> 'sourceFingerprint' !~ '^[0-9a-f]{64}$'
       or item ->> 'startLocal' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:(00|30)$'
       or item ->> 'endLocal' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:(00|30)$'
       or item ->> 'durationMinutes' !~ '^[0-9]+$'
       or (item ->> 'durationMinutes')::integer < 60
       or (item ->> 'durationMinutes')::integer % 30 <> 0
       or item ->> 'useType' not in ('individual', 'group')
       or (item -> 'bookingTitle' <> 'null'::jsonb and (jsonb_typeof(item -> 'bookingTitle') <> 'string' or length(item ->> 'bookingTitle') > 100))
  ) then
    raise exception 'A foglalási payload tiltott, hiányzó vagy hibás mezőt tartalmaz.' using errcode = '22023';
  end if;
  if (select count(distinct item ->> 'sourceFingerprint') from jsonb_array_elements(p_bookings) item) <> jsonb_array_length(p_bookings) then
    raise exception 'A forrás-ujjlenyomatok nem egyediek.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_bookings) item
    where (item ->> 'startLocal')::timestamp >= (item ->> 'endLocal')::timestamp
       or (item ->> 'startLocal')::timestamp::date <> (item ->> 'endLocal')::timestamp::date
       or extract(epoch from ((item ->> 'endLocal')::timestamp - (item ->> 'startLocal')::timestamp)) / 60 <> (item ->> 'durationMinutes')::integer
       or (item ->> 'useType') = 'group' and (item ->> 'roomName') <> 'Tréningterem'
       or not exists (select 1 from public.rooms room where room.name = item ->> 'roomName' and room.is_active)
  ) then
    raise exception 'A foglalási időpont, helyiség vagy használati típus hibás.' using errcode = '22023';
  end if;

  select array_agg(group_name order by group_name) into v_expected_groups
  from (
    select distinct case
      when item ->> 'roomName' in ('Gyerek szoba', 'Pitypang szoba', 'Csoport szoba') then 'A-Hely'
      when item ->> 'roomName' in ('1.Szoba-családi', '2.Szoba', '3.Szoba', '4.Szoba', '5.Szoba', '6.Szoba') then 'Másik Hely'
      when item ->> 'roomName' = 'Tréningterem' then 'Tréningterem'
      when item ->> 'roomName' = 'Forrás tér' then 'Forrás tér'
      else null
    end group_name
    from jsonb_array_elements(p_bookings) item
  ) expected where group_name is not null;
  if coalesce(array_length(v_expected_groups, 1), 0) = 0
     or coalesce((select array_agg(name order by name) from (select distinct unnest(p_access_group_names) name) names), '{}'::text[]) <> v_expected_groups
     or exists (select 1 from unnest(v_expected_groups) name where not exists (select 1 from public.access_groups where access_groups.name = name and is_active)) then
    raise exception 'A kért helyiségcsoportok nem egyeznek a foglalásokból levezetett jogosultságokkal.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_bookings) item
    join public.rooms room on room.name = item ->> 'roomName' and room.is_active
    where not exists (
      select 1 from public.access_groups access_group
      join public.access_group_rooms access_room on access_room.group_id = access_group.id
      where access_group.name = case
        when room.name in ('Gyerek szoba', 'Pitypang szoba', 'Csoport szoba') then 'A-Hely'
        when room.name in ('1.Szoba-családi', '2.Szoba', '3.Szoba', '4.Szoba', '5.Szoba', '6.Szoba') then 'Másik Hely'
        when room.name = 'Tréningterem' then 'Tréningterem'
        when room.name = 'Forrás tér' then 'Forrás tér'
      end and access_room.room_id = room.id and access_room.can_book
    )
  ) then
    raise exception 'A helyiségcsoport nem ad foglalási jogot valamelyik célhelyiségre.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('allbooked:' || v_email, 0));
  if exists (select 1 from public.bookings booking where booking.user_id = p_user_id and not exists (select 1 from public.allbooked_migration_bookings ledger where ledger.booking_id = booking.id))
     or exists (select 1 from public.access_group_members member join public.access_groups access_group on access_group.id = member.group_id where member.user_id = p_user_id and access_group.name <> all(v_expected_groups))
     or exists (select 1 from public.user_room_permissions where user_id = p_user_id)
     or exists (select 1 from public.user_price_overrides where user_id = p_user_id)
     or exists (select 1 from public.monthly_settlements where user_id = p_user_id)
     or exists (select 1 from public.profiles where id = p_user_id and onboarding_completed_at is not null) then
    raise exception 'A céluser meglévő üzleti adatai miatt az automatikus import lezárult.' using errcode = 'P0001';
  end if;

  select to_jsonb(profile) into v_before from public.profiles profile where id = p_user_id for update;
  update public.profiles
  set first_name = trim(p_first_name), last_name = trim(p_last_name), phone = p_phone, is_active = true, updated_at = clock_timestamp()
  where id = p_user_id and (first_name is distinct from trim(p_first_name) or last_name is distinct from trim(p_last_name) or phone is distinct from p_phone or not is_active);
  select to_jsonb(profile) into v_after from public.profiles profile where id = p_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (p_actor_id, 'allbooked.profile_imported', 'profile', p_user_id::text, v_before, v_after, p_correlation_id);
  end if;

  for v_group_id in
    select access_group.id from public.access_groups access_group
    where access_group.name = any(v_expected_groups)
      and not exists (select 1 from public.access_group_members member where member.group_id=access_group.id and member.user_id=p_user_id)
  loop
    insert into public.access_group_members(group_id,user_id) values (v_group_id,p_user_id);
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values (p_actor_id,'allbooked.access_imported','access_group_member',v_group_id::text || ':' || p_user_id::text,
      jsonb_build_object('group_id',v_group_id,'user_id',p_user_id,'source','allbooked'),p_correlation_id);
  end loop;

  for v_item in select item from jsonb_array_elements(p_bookings) item order by item ->> 'startLocal', item ->> 'roomName' loop
    select * into strict v_room from public.rooms where name = v_item ->> 'roomName' and is_active;
    v_start_at := (v_item ->> 'startLocal')::timestamp at time zone 'Europe/Budapest';
    v_end_at := (v_item ->> 'endLocal')::timestamp at time zone 'Europe/Budapest';
    select booking.* into v_existing
    from public.allbooked_migration_bookings ledger join public.bookings booking on booking.id = ledger.booking_id
    where ledger.source_fingerprint = v_item ->> 'sourceFingerprint';
    if found then
      if v_existing.user_id <> p_user_id or v_existing.room_id <> v_room.id or v_existing.start_at <> v_start_at or v_existing.end_at <> v_end_at
         or v_existing.use_type::text <> v_item ->> 'useType' or v_existing.status <> 'active' or v_existing.series_id is not null
         or v_existing.note is not null or v_existing.booking_title is distinct from nullif(v_item ->> 'bookingTitle', '') then
        raise exception 'Az idempotens újrafuttatás eltérő meglévő foglalást talált.' using errcode = 'P0001';
      end if;
      v_existing_count := v_existing_count + 1;
    else
      if exists (select 1 from public.bookings where room_id = v_room.id and status = 'active' and time_range && tstzrange(v_start_at, v_end_at, '[)')) then
        raise exception 'A migrált időpontra aktív foglalási ütközés található.' using errcode = '23P01';
      end if;
      insert into public.bookings(room_id,user_id,created_by,start_at,end_at,use_type,status,note,booking_title,idempotency_key)
      values (v_room.id,p_user_id,p_actor_id,v_start_at,v_end_at,(v_item ->> 'useType')::public.booking_use_type,'active',null,nullif(v_item ->> 'bookingTitle',''),gen_random_uuid())
      returning id into v_booking_id;
      insert into public.allbooked_migration_bookings(source_fingerprint,booking_id,user_id,imported_by)
      values (v_item ->> 'sourceFingerprint',v_booking_id,p_user_id,p_actor_id);
      insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,reason,correlation_id)
      values (p_actor_id,'allbooked.booking_imported','booking',v_booking_id::text,
        jsonb_build_object('room_id',v_room.id,'user_id',p_user_id,'start_at',v_start_at,'end_at',v_end_at,'use_type',v_item ->> 'useType','source_fingerprint',v_item ->> 'sourceFingerprint','legacy_price_imported',false,'legacy_payment_imported',false),
        'AllBooked customer migration',p_correlation_id);
      v_created := v_created + 1;
    end if;
  end loop;

  select jsonb_build_object(
    'valid', count(*) = jsonb_array_length(p_bookings)
      and count(*) = (select count(*) from public.allbooked_migration_bookings where user_id = p_user_id and source_fingerprint in (select item ->> 'sourceFingerprint' from jsonb_array_elements(p_bookings) item)),
    'userId', p_user_id, 'email', v_email, 'accessGroups', to_jsonb(v_expected_groups),
    'bookings', count(*), 'created', v_created, 'existing', v_existing_count,
    'totalMinutes', coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/60),0)::integer,
    'firstServiceDate', min((booking.start_at at time zone 'Europe/Budapest')::date),
    'lastServiceDate', max((booking.start_at at time zone 'Europe/Budapest')::date),
    'trainingIndividual', count(*) filter (where room.name='Tréningterem' and booking.use_type='individual'),
    'trainingGroup', count(*) filter (where room.name='Tréningterem' and booking.use_type='group'),
    'migrationLedgerRows', (select count(*) from public.allbooked_migration_bookings where user_id=p_user_id and source_fingerprint in (select item ->> 'sourceFingerprint' from jsonb_array_elements(p_bookings) item)),
    'legacyFinancialRows', (select count(*) from public.user_price_overrides where user_id=p_user_id) + (select count(*) from public.monthly_settlements where user_id=p_user_id)
  ) into v_result
  from public.bookings booking join public.rooms room on room.id=booking.room_id
  where booking.user_id=p_user_id and booking.status='active'
    and booking.id in (
      select ledger.booking_id from public.allbooked_migration_bookings ledger
      where ledger.user_id=p_user_id and ledger.source_fingerprint in (select item ->> 'sourceFingerprint' from jsonb_array_elements(p_bookings) item)
    );
  if not coalesce((v_result ->> 'valid')::boolean,false) then
    raise exception 'Az AllBooked import reconciliation eltérést talált.' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.admin_void_papp_dalma_test_import(
  p_actor_id uuid,
  p_confirmation text,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_booking record;
  v_voided integer := 0;
  v_result jsonb;
begin
  if p_confirmation <> 'REMOVE-PAPP-DALMA-TEST-DATA' or p_correlation_id is null then
    raise exception 'A Papp Dalma próbaadat-visszavonás megerősítése hibás.' using errcode='22023';
  end if;
  if not exists (select 1 from public.profiles where id=p_actor_id and role='admin' and is_active) then
    raise exception 'A próbaadat-visszavonást csak aktív admin futtathatja.' using errcode='42501';
  end if;
  select id into v_user_id from public.profiles where email='pappdalma17@gmail.com' and role='user';
  if v_user_id is null or not exists (select 1 from auth.users where id=v_user_id and lower(email)='pappdalma17@gmail.com') then
    raise exception 'A Papp Dalma próbauser Auth/profile azonossága nem bizonyítható.' using errcode='P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('allbooked:pappdalma17@gmail.com',0));
  if (select count(*) from public.allbooked_migration_bookings where user_id=v_user_id) <> 21
     or (select count(*) from public.bookings where user_id=v_user_id) <> 21
     or exists (
       select 1 from public.allbooked_migration_bookings ledger join public.bookings booking on booking.id=ledger.booking_id
       join public.rooms room on room.id=booking.room_id
       where ledger.user_id=v_user_id and (
         room.name <> 'Forrás tér' or booking.use_type <> 'individual' or booking.series_id is not null
         or booking.note is not null or booking.booking_title is not null
         or (booking.start_at at time zone 'Europe/Budapest')::date not between date '2026-09-03' and date '2026-09-17'
         or booking.status::text not in ('active','voided')
       )
     )
     or (select coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/60),0) from public.bookings booking where booking.user_id=v_user_id) <> 1320
     or (select count(*) from public.bookings booking where booking.user_id=v_user_id and extract(epoch from (booking.end_at-booking.start_at))/60=60) <> 19
     or (select count(*) from public.bookings booking where booking.user_id=v_user_id and extract(epoch from (booking.end_at-booking.start_at))/60=90) <> 2
     or (select min((booking.start_at at time zone 'Europe/Budapest')::date) from public.bookings booking where booking.user_id=v_user_id) <> date '2026-09-03'
     or (select max((booking.start_at at time zone 'Europe/Budapest')::date) from public.bookings booking where booking.user_id=v_user_id) <> date '2026-09-17'
     or exists (select 1 from public.user_room_permissions where user_id=v_user_id)
     or exists (select 1 from public.user_price_overrides where user_id=v_user_id)
     or exists (select 1 from public.monthly_settlements where user_id=v_user_id)
     or exists (select 1 from public.settlement_booking_lines line join public.bookings booking on booking.id=line.booking_id where booking.user_id=v_user_id)
     or exists (select 1 from public.booking_cancellations cancellation join public.bookings booking on booking.id=cancellation.booking_id where booking.user_id=v_user_id)
     or exists (select 1 from public.profiles where id=v_user_id and onboarding_completed_at is not null)
     or exists (select 1 from public.access_group_members member join public.access_groups access_group on access_group.id=member.group_id where member.user_id=v_user_id and access_group.name <> 'Forrás tér') then
    raise exception 'A Papp Dalma profil már nem egyezik a bizonyított 21 foglalásos próbaimporttal; automatikus visszavonás tilos.' using errcode='P0001';
  end if;

  for v_booking in
    select booking.id,booking.status from public.bookings booking
    join public.allbooked_migration_bookings ledger on ledger.booking_id=booking.id
    where ledger.user_id=v_user_id and booking.status='active'
    order by booking.start_at
  loop
    update public.bookings set status='voided',updated_at=clock_timestamp() where id=v_booking.id;
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
    values (p_actor_id,'allbooked.test_booking_voided','booking',v_booking.id::text,
      jsonb_build_object('status','active'),jsonb_build_object('status','voided'),
      'Papp Dalma 21-booking migration trial removed before customer cutover',p_correlation_id);
    v_voided := v_voided+1;
  end loop;

  if exists (select 1 from public.access_group_members where user_id=v_user_id) then
    delete from public.access_group_members where user_id=v_user_id;
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,reason,correlation_id)
    values (p_actor_id,'allbooked.test_access_removed','profile',v_user_id::text,
      jsonb_build_object('all_access_groups_removed',true),'Papp Dalma migration trial cleanup',p_correlation_id);
  end if;
  select to_jsonb(profile) into v_before from public.profiles profile where id=v_user_id for update;
  update public.profiles set is_active=false,phone=null,updated_at=clock_timestamp() where id=v_user_id;
  select to_jsonb(profile) into v_after from public.profiles profile where id=v_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
    values (p_actor_id,'allbooked.test_profile_reset','profile',v_user_id::text,v_before,v_after,
      'Papp Dalma migration trial cleanup; profile retained for later real re-import',p_correlation_id);
  end if;
  select jsonb_build_object(
    'valid', (select count(*)=0 from public.bookings where user_id=v_user_id and status='active')
      and (select count(*)=21 from public.bookings where user_id=v_user_id and status='voided')
      and (select count(*)=0 from public.access_group_members where user_id=v_user_id)
      and (select not is_active and phone is null from public.profiles where id=v_user_id),
    'email','pappdalma17@gmail.com','voidedNow',v_voided,'voidedBookings',21,
    'activeBookings',0,'profileActive',false,'readyForRealReimport',true
  ) into v_result;
  if not coalesce((v_result ->> 'valid')::boolean,false) then
    raise exception 'A Papp Dalma próbaadat-visszavonás reconciliation eltérést talált.' using errcode='P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.admin_rollback_empty_allbooked_profile(p_actor_id uuid,p_user_id uuid,p_email text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if not exists (select 1 from public.profiles where id=p_actor_id and role='admin' and is_active) then
    raise exception 'A kompenzáló törlést csak aktív admin futtathatja.' using errcode='42501';
  end if;
  if not exists (select 1 from auth.users where id=p_user_id and lower(email)=lower(trim(p_email)))
     or not exists (select 1 from public.profiles where id=p_user_id and email=lower(trim(p_email)) and onboarding_completed_at is null) then
    raise exception 'A kompenzáló törlés célja nem azonosítható.' using errcode='P0001';
  end if;
  if exists (select 1 from public.bookings where user_id=p_user_id or created_by=p_user_id)
     or exists (select 1 from public.allbooked_migration_bookings where user_id=p_user_id or imported_by=p_user_id)
     or exists (select 1 from public.access_group_members where user_id=p_user_id)
     or exists (select 1 from public.user_room_permissions where user_id=p_user_id)
     or exists (select 1 from public.user_price_overrides where user_id=p_user_id)
     or exists (select 1 from public.monthly_settlements where user_id=p_user_id)
     or exists (select 1 from public.audit_logs where actor_user_id=p_user_id or entity_id=p_user_id::text) then
    raise exception 'A kompenzáló törlés nem biztonságos: kapcsolódó adat található.' using errcode='P0001';
  end if;
  delete from public.profiles where id=p_user_id;
  return found;
end;
$$;

revoke all on function public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid) from public,anon,authenticated;
revoke all on function public.admin_rollback_empty_allbooked_profile(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.admin_void_papp_dalma_test_import(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid) to service_role;
grant execute on function public.admin_rollback_empty_allbooked_profile(uuid,uuid,text) to service_role;
grant execute on function public.admin_void_papp_dalma_test_import(uuid,text,uuid) to service_role;

comment on function public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid) is
  'Fail-closed, idempotent and atomic one-customer AllBooked import. Service role only; excludes notes and legacy financial data.';
comment on function public.admin_void_papp_dalma_test_import(uuid,text,uuid) is
  'One-time fail-closed logical removal of the proven 21-booking Papp Dalma trial. Preserves immutable audit evidence and permits later real re-import.';

commit;
