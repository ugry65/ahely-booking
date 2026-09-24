begin;

select plan(40);

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
  $$select public.admin_rollback_empty_allbooked_profile(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000113','ugyfel-ketto@example.invalid')$$,
  'Az üres, üzleti adat nélküli profil kompenzáló törlése sikeres'
);
reset role;
select is((select count(*) from public.profiles where id='00000000-0000-0000-0000-000000000113'),0::bigint,'A kompenzáló törlés után nem marad üres profil');

select ok(not has_function_privilege('authenticated','public.admin_void_papp_dalma_test_import(uuid,text,uuid)','EXECUTE'),'Az authenticated nem vonhatja vissza a próbaimportot');
select ok(has_function_privilege('service_role','public.admin_void_papp_dalma_test_import(uuid,text,uuid)','EXECUTE'),'A próbaimport-visszavonás service role művelet');

insert into auth.users(id,email,raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000114','pappdalma17@gmail.com','{"first_name":"Dalma","last_name":"Papp"}');
update public.profiles set phone='+36307337981' where id='00000000-0000-0000-0000-000000000114';
create temp table papp_trial_rows(id uuid,source_fingerprint text,start_at timestamptz,end_at timestamptz);
insert into papp_trial_rows
select gen_random_uuid(),encode(digest('papp-trial-' || item.i::text,'sha256'),'hex'),item.start_at,item.start_at+make_interval(mins=>item.duration_minutes)
from (
  select i,timestamptz '2026-09-03 06:00:00+00'+make_interval(days=>i-1) start_at,60 duration_minutes from generate_series(1,15) i
  union all
  select i,timestamptz '2026-09-03 08:00:00+00'+make_interval(days=>i-16),60 from generate_series(16,19) i
  union all select 20,timestamptz '2026-09-07 08:00:00+00',90
  union all select 21,timestamptz '2026-09-08 08:00:00+00',90
) item;
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,note,booking_title,idempotency_key)
select row.id,(select id from public.rooms where name='Forrás tér'),'00000000-0000-0000-0000-000000000114','00000000-0000-0000-0000-000000000111',row.start_at,row.end_at,'individual','active',null,null,gen_random_uuid()
from papp_trial_rows row;
insert into public.allbooked_migration_bookings(source_fingerprint,booking_id,user_id,imported_by)
select source_fingerprint,id,'00000000-0000-0000-0000-000000000114','00000000-0000-0000-0000-000000000111' from papp_trial_rows;
insert into public.access_group_members(group_id,user_id)
values ((select id from public.access_groups where name='Forrás tér'),'00000000-0000-0000-0000-000000000114');

set local role service_role;
select lives_ok(
  $$select public.admin_void_papp_dalma_test_import(
    '00000000-0000-0000-0000-000000000111','REMOVE-PAPP-DALMA-TEST-DATA','11000000-0000-0000-0000-000000000007')$$,
  'A pontosan azonosított 21 foglalásos próbaimport visszavonható'
);
reset role;
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000114' and status='voided'),21::bigint,'Mind a 21 próba-foglalás voided állapotú');
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000114' and status='active'),0::bigint,'Nem maradt aktív Papp Dalma próba-foglalás');
select is((select count(*) from public.access_group_members where user_id='00000000-0000-0000-0000-000000000114'),0::bigint,'A próba során kiosztott csoportjog megszűnt');
select is((select is_active::text || '|' || coalesce(phone,'—') from public.profiles where id='00000000-0000-0000-0000-000000000114'),'false|—','A próba-profil inaktív, üres újraimportállapotú');

set local role service_role;
select lives_ok(
  $$select public.admin_import_allbooked_customer(
    '00000000-0000-0000-0000-000000000111','00000000-0000-0000-0000-000000000114','pappdalma17@gmail.com',
    'Dalma','Papp','+36301111111',array['Forrás tér'],
    jsonb_build_array(jsonb_build_object('sourceFingerprint',encode(digest('papp-real-v2','sha256'),'hex'),'roomName','Forrás tér','startLocal','2026-09-03 08:00','endLocal','2026-09-03 09:00','durationMinutes',60,'bookingTitle','Valós foglalás','note',null,'useType','individual')),
    '11000000-0000-0000-0000-000000000008')$$,
  'A voidolt próba után Papp Dalma valós adata újramigrálható'
);
reset role;
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000114' and status='active'),1::bigint,'Az újraimport pontosan egy aktív valós foglalást hozott létre');
select is((select count(*) from public.bookings where user_id='00000000-0000-0000-0000-000000000114' and status='voided'),21::bigint,'A régi próba bizonyítéka voidolt állapotban elkülönül');
select is((select is_active::text || '|' || phone from public.profiles where id='00000000-0000-0000-0000-000000000114'),'true|+36301111111','A valós újraimport újraaktiválja és frissíti a profilt');

select * from finish();
rollback;
