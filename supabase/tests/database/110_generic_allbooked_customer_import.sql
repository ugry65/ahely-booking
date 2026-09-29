begin;

select plan(35);

select has_function('public','admin_import_allbooked_customer',array['uuid','uuid','text','text','text','text','text[]','jsonb','uuid'],'Az általános ügyfélimport függvény létezik');
select ok(not has_function_privilege('authenticated','public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid)','EXECUTE'),'Az authenticated nem hívhatja az importot');
select ok(has_function_privilege('service_role','public.admin_import_allbooked_customer(uuid,uuid,text,text,text,text,text[],jsonb,uuid)','EXECUTE'),'A service role hívhatja az importot');

insert into auth.users(id,email,raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000111','generic-migration-admin@example.invalid','{"first_name":"Generic","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid','{"first_name":"Egy","last_name":"Ugyfel"}'),
  ('00000000-0000-0000-0000-000000000113','ugyfel-ketto@example.invalid','{"first_name":"Ketto","last_name":"Ugyfel"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000111';

create temp table generic_payload(data jsonb);
insert into generic_payload values (jsonb_build_array(
  jsonb_build_object('sourceFingerprint',encode(digest('generic-1','sha256'),'hex'),'roomName','Forrás tér','startLocal','2031-02-03 08:00','endLocal','2031-02-03 09:00','durationMinutes',60,'bookingTitle','Első foglalás','note','+36 30 484 8529 – fontos migrált információ','useType','individual'),
  jsonb_build_object('sourceFingerprint',encode(digest('generic-2','sha256'),'hex'),'roomName','Tréningterem','startLocal','2031-02-04 09:00','endLocal','2031-02-04 10:30','durationMinutes',90,'bookingTitle','Egyéni tréning','note',null,'useType','individual'),
  jsonb_build_object('sourceFingerprint',encode(digest('generic-3','sha256'),'hex'),'roomName','Tréningterem','startLocal','2031-02-05 10:00','endLocal','2031-02-05 12:00','durationMinutes',120,'bookingTitle','Csoport','note',null,'useType','group')
));
grant select on generic_payload to service_role;

set local role service_role;
select lives_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér','Tréningterem'],(select data from pg_temp.generic_payload),
    '11000000-0000-0000-0000-000000000001')$$,
  'Az egy ügyfélhez tartozó vegyes foglalások atomikusan importálhatók'
);
reset role;

select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000112'),3::bigint,'Pontosan három foglalás jött létre');
select is((select count(*) from public.allbooked_migration_bookings where user_id='00000000-0000-0000-0000-000000000112'),3::bigint,'Mindhárom foglalás bekerült az immutable ledgerbe');
select is((select concat_ws('|',first_name,last_name,email,phone,role::text,is_active::text) from public.profiles where id='00000000-0000-0000-0000-000000000112'),'Egy|Ugyfel|ugyfel-egy@example.invalid|+36301234567|user|true','A profiladatok pontosak');
select is((select string_agg(access_group.name,',' order by access_group.name) from public.access_group_members member join public.access_groups access_group on access_group.id=member.group_id where member.user_id='00000000-0000-0000-0000-000000000112'),'Forrás tér,Tréningterem','Csak a foglalásokból levezetett csoportjogok jöttek létre');
select is((select string_agg(booking.use_type::text,',' order by booking.start_at) from public.bookings booking where booking.user_id='00000000-0000-0000-0000-000000000112'),'individual,individual,group','A Tréningterem egyéni/csoportos besorolása megmaradt');
select is((select string_agg(coalesce(booking_title,'—'),',' order by start_at) from public.bookings where user_id='00000000-0000-0000-0000-000000000112'),'Első foglalás,Egyéni tréning,Csoport','A foglalási megnevezések megmaradtak');
select is((select note from public.bookings where user_id='00000000-0000-0000-0000-000000000112' order by start_at limit 1),'+36 30 484 8529 – fontos migrált információ','Az AllBooked megjegyzés változtatás nélkül megmaradt a foglaláson');
select is((select count(*) from public.audit_logs where correlation_id='11000000-0000-0000-0000-000000000001' and coalesce(after_data::text,'') like '%484 8529%'),0::bigint,'A megjegyzés tartalma nem duplikálódik az audit payloadba');
select is((select count(*) from public.user_price_overrides where user_id='00000000-0000-0000-0000-000000000112')+(select count(*) from public.monthly_settlements where user_id='00000000-0000-0000-0000-000000000112'),0::bigint,'Legacy ár és fizetési adat nem jött létre');
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000112' and hourly_rate_override_huf is not null),0::bigint,'Az AllBooked import nem hozott létre véletlen foglalásszintű ár-felülírást');
select is((select count(*) from public.audit_logs where action='allbooked.booking_imported' and correlation_id='11000000-0000-0000-0000-000000000001'),3::bigint,'Minden importált foglalás auditált');

set local role service_role;
select lives_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Tréningterem','Forrás tér'],(select data from pg_temp.generic_payload),
    '11000000-0000-0000-0000-000000000002')$$,
  'Az azonos forrás idempotensen újrafuttatható'
);
reset role;
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000112'),3::bigint,'Az újrafuttatás nem duplikál foglalást');
select is((select count(*) from public.audit_logs where action='allbooked.booking_imported' and entity_id in (select booking_id::text from public.allbooked_migration_bookings where user_id='00000000-0000-0000-0000-000000000112')),3::bigint,'Az újrafuttatás nem duplikál foglalásauditot');

create temp table altered_payload(data jsonb);
insert into altered_payload
select jsonb_set(data, '{0,bookingTitle}', '"Megváltozott foglalás"'::jsonb) from generic_payload;
grant select on altered_payload to service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér','Tréningterem'],(select data from pg_temp.altered_payload),
    '11000000-0000-0000-0000-000000000009')$$,
  'P0001','Az idempotens újrafuttatás eltérő meglévő foglalást talált.','Az azonos fingerprint eltérő payloadja fail-closed módon elutasított'
);
reset role;

create temp table altered_note_payload(data jsonb);
insert into altered_note_payload
select jsonb_set(data, '{0,note}', '"Megváltozott megjegyzés"'::jsonb) from generic_payload;
grant select on altered_note_payload to service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér','Tréningterem'],(select data from pg_temp.altered_note_payload),
    '11000000-0000-0000-0000-000000000010')$$,
  'P0001','Az idempotens újrafuttatás eltérő meglévő foglalást talált.','Azonos fingerprint mellett a megjegyzés eltérése is fail-closed'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér'],(select data from pg_temp.generic_payload),
    '11000000-0000-0000-0000-000000000003')$$,
  '22023','A kért helyiségcsoportok nem egyeznek a foglalásokból levezetett jogosultságokkal.','A hiányos helyiségcsoport-lista fail-closed módon elutasított'
);
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000112','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér','Tréningterem'],(select data from pg_temp.generic_payload),
    '11000000-0000-0000-0000-000000000004')$$,
  '42501','Az importot csak aktív admin futtathatja.','Nem admin nem indíthat importot'
);
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000112','ugyfel-egy@example.invalid',
    'Egy','Ugyfel','+36301234567',array['Forrás tér'],
    jsonb_build_array(jsonb_build_object('sourceFingerprint',encode(digest('bad-group','sha256'),'hex'),'roomName','Forrás tér','startLocal','2031-03-01 08:00','endLocal','2031-03-01 09:00','durationMinutes',60,'bookingTitle',null,'note',null,'useType','group')),
    '11000000-0000-0000-0000-000000000005')$$,
  '22023','A foglalási időpont, helyiség vagy használati típus hibás.','Nem tréninghelyiség nem lehet csoportos használatú'
);
reset role;

insert into public.bookings(room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ((select id from public.rooms where name='Forrás tér'),'00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000111','2031-04-02 06:00+00','2031-04-02 07:00+00','individual','active',gen_random_uuid());
create temp table conflicting_payload(data jsonb);
insert into conflicting_payload values (jsonb_build_array(
  jsonb_build_object('sourceFingerprint',encode(digest('atomic-1','sha256'),'hex'),'roomName','Tréningterem','startLocal','2031-04-01 08:00','endLocal','2031-04-01 09:00','durationMinutes',60,'bookingTitle',null,'note',null,'useType','individual'),
  jsonb_build_object('sourceFingerprint',encode(digest('atomic-2','sha256'),'hex'),'roomName','Forrás tér','startLocal','2031-04-02 08:00','endLocal','2031-04-02 09:00','durationMinutes',60,'bookingTitle',null,'note',null,'useType','individual')
));
grant select on conflicting_payload to service_role;
set local role service_role;
select throws_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000113','ugyfel-ketto@example.invalid',
    'Ketto','Ugyfel',null,array['Forrás tér','Tréningterem'],(select data from pg_temp.conflicting_payload),
    '11000000-0000-0000-0000-000000000006')$$,
  '23P01','A migrált időpontra aktív foglalási ütközés található.','Egy későbbi ütközés az egész ügyfélimportot visszagörgeti'
);
reset role;
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000113'),0::bigint,'Ütközés után nem maradt részleges foglalás');
select is((select count(*) from public.access_group_members where user_id='00000000-0000-0000-0000-000000000113'),0::bigint,'Ütközés után nem maradt részleges jogosultság');
select is((select count(*) from public.allbooked_migration_bookings where user_id='00000000-0000-0000-0000-000000000113'),0::bigint,'Ütközés után nem maradt ledgerrekord');

set local role service_role;
select lives_ok(
  $$select public.admin_cleanup_failed_allbooked_auth_profile(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000113','ugyfel-ketto@example.invalid')$$,
  'A jelenlegi kompenzáció eltávolítja az üres, üzleti adat nélküli profilt'
);
reset role;
select is((select count(*) from public.profiles where id='00000000-0000-0000-0000-000000000113'),0::bigint,'Az aktuális kompenzáció után nem marad üres profil');
select ok('voided' = any(enum_range(null::public.booking_status)::text[]),'A történeti voided státusz az adatmodell része');
select ok(not exists (select 1 from pg_proc where oid=to_regprocedure('public.admin_void_papp_dalma_test_import(uuid,text,uuid)')),'A próba-visszavonó RPC már nincs a runtime sémában');
select ok(not exists (select 1 from pg_proc where oid=to_regprocedure('public.admin_rollback_empty_allbooked_profile(uuid,uuid,text)')),'A régi kompenzációs RPC már nincs a runtime sémában');
select ok(not exists (select 1 from pg_proc where oid=to_regprocedure('public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid)')),'A régi Papp import RPC hiányzik');
select ok(not exists (select 1 from pg_proc where oid=to_regprocedure('public.admin_reconcile_papp_dalma_allbooked(uuid,text[])')),'A régi Papp egyeztető RPC hiányzik');
select ok(not exists (select 1 from pg_proc where oid=to_regprocedure('public.admin_rollback_empty_papp_dalma_profile(uuid,uuid)')),'A régi Papp kompenzációs RPC hiányzik');

select * from finish();
rollback;
