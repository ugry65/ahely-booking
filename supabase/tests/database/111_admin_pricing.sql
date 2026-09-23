begin;

select plan(58);

select has_column('public','bookings','hourly_rate_override_huf','A foglalásszintű óradíj-felülírás tárolható');
select has_column('public','settlement_booking_lines','rate_source','A settlement sor megőrzi az alkalmazott árforrást');
select has_function('public','admin_pricing_quote',array['uuid','uuid','timestamp with time zone','timestamp with time zone','booking_use_type','uuid','bigint'],'Az admin díjelőnézet RPC létezik');
select has_function('public','admin_set_user_hourly_rate',array['uuid','bigint','date','text','uuid'],'A user egyedi díj admin RPC létezik');
select has_function('public','admin_create_booking_with_pricing',array['uuid','uuid','timestamp with time zone','timestamp with time zone','booking_use_type','text','uuid','text','bigint','text'],'Az atomikus admin booking+díj RPC létezik');
select has_function('public','admin_create_monthly_settlement_revision',array['uuid','date','text','uuid'],'Az auditált havi settlement revision RPC létezik');
select ok(not has_function_privilege('anon','public.admin_set_booking_hourly_rate_override(uuid,bigint,text,uuid)','EXECUTE'),'Anon nem módosíthat foglalási árat');

select is((select hourly_rate_huf from public.pricing_tiers where min_minutes=60 and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),2500::bigint,'1–15 óra központi díja 2 500 Ft');
select is((select hourly_rate_huf from public.pricing_tiers where 900 between min_minutes and coalesce(max_minutes,2147483647) and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),2500::bigint,'A pontos 15 órás sávhatár még 2 500 Ft');
select is((select hourly_rate_huf from public.pricing_tiers where 901 between min_minutes and coalesce(max_minutes,2147483647) and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),1900::bigint,'A 15 óra feletti első perc már 1 900 Ft');
select is((select hourly_rate_huf from public.pricing_tiers where 930 between min_minutes and coalesce(max_minutes,2147483647) and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),1900::bigint,'15 óra felett a központi díj 1 900 Ft');
select is((select hourly_rate_huf from public.pricing_tiers where 3600 between min_minutes and coalesce(max_minutes,2147483647) and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),1900::bigint,'A 60 órás sávhatár még 1 900 Ft');
select is((select hourly_rate_huf from public.pricing_tiers where 3630 between min_minutes and coalesce(max_minutes,2147483647) and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),1700::bigint,'60 óra felett a központi díj 1 700 Ft');
select is((select count(*) from public.audit_logs where action='pricing.central_schedule_migrated' and entity_type='pricing_tiers' and entity_id='2026-10-01' and actor_user_id is null and correlation_id is not null and nullif(btrim(reason),'') is not null),1::bigint,'A központi induló tarifamigráció egy rendszer-eredetű auditbejegyzést hoz létre');
select is((select string_agg((tier->>'min_minutes')||':'||coalesce(tier->>'max_minutes','*')||':'||(tier->>'hourly_rate_huf'),',' order by (tier->>'min_minutes')::integer) from public.audit_logs audit cross join lateral jsonb_array_elements(audit.before_data) tier where audit.action='pricing.central_schedule_migrated'),'60:900:2700,901:3600:1900,3601:*:1700','A központi tarifamigráció auditja megőrzi a teljes előző díjsort');
select is((select string_agg((tier->>'min_minutes')||':'||coalesce(tier->>'max_minutes','*')||':'||(tier->>'hourly_rate_huf'),',' order by (tier->>'min_minutes')::integer) from public.audit_logs audit cross join lateral jsonb_array_elements(audit.after_data) tier where audit.action='pricing.central_schedule_migrated'),'60:900:2500,901:3600:1900,3601:*:1700','A központi tarifamigráció auditja megőrzi a teljes új díjsort');
select is((select hourly_rate_huf from public.special_room_rates where room_id='11000000-0000-0000-0000-000000000001' and use_type='group' and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),5000::bigint,'A Tréningterem csoportos alapdíja 5 000 Ft');
select is((select count(*) from public.special_room_rates where room_id='11000000-0000-0000-0000-000000000001' and use_type='group' and date '2026-10-01' between valid_from and coalesce(valid_to,'infinity'::date)),1::bigint,'A Tréningteremhez pontosan egy tarifa érvényes 2026-10-01-én');
select is((select max(valid_to) from public.special_room_rates where room_id='11000000-0000-0000-0000-000000000001' and use_type='group' and valid_from<date '2026-10-01'),date '2026-09-30','A korábbi Tréningterem-tarifa 2026-09-30-án lezárul');
select is((select count(*) from public.audit_logs where action='pricing.training_room_rate_migrated' and entity_id='11000000-0000-0000-0000-000000000001' and (after_data->>'hourly_rate_huf')::bigint=5000),1::bigint,'Az 5 000 Ft-os Tréningterem-tarifa migrációja auditált');

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000181','pricing-admin@example.invalid','{"first_name":"Pricing","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000182','pricing-central@example.invalid','{"first_name":"Central","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000183','pricing-training@example.invalid','{"first_name":"Training","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000184','pricing-fixed@example.invalid','{"first_name":"Fixed","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000185','pricing-booking@example.invalid','{"first_name":"Booking","last_name":"User"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000181';

insert into public.user_price_overrides(user_id,hourly_rate_huf,valid_from,reason,created_by) values
 ('00000000-0000-0000-0000-000000000184',3200,'2026-10-01','Teszt user díj','00000000-0000-0000-0000-000000000181'),
 ('00000000-0000-0000-0000-000000000185',3200,'2026-10-01','Teszt user díj','00000000-0000-0000-0000-000000000181');

insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason) values
 ('41000000-0000-0000-0000-000000000181','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000182','00000000-0000-0000-0000-000000000181','2035-10-05 07:00+02','2035-10-05 08:00+02','individual','active',gen_random_uuid(),null,null,null,null),
 ('41000000-0000-0000-0000-000000000182','11000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000183','00000000-0000-0000-0000-000000000181','2035-10-06 07:00+02','2035-10-06 08:00+02','group','active',gen_random_uuid(),null,null,null,null),
 ('41000000-0000-0000-0000-000000000183','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000184','00000000-0000-0000-0000-000000000181','2035-10-07 07:00+02','2035-10-07 08:00+02','individual','active',gen_random_uuid(),null,null,null,null),
 ('41000000-0000-0000-0000-000000000184','11000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000185','00000000-0000-0000-0000-000000000181','2035-10-08 07:00+02','2035-10-08 08:00+02','group','active',gen_random_uuid(),4100,'00000000-0000-0000-0000-000000000181',now(),'Teszt booking felülírás'),
 ('41000000-0000-0000-0000-000000000186','11000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000184','00000000-0000-0000-0000-000000000181','2035-11-08 07:00+02','2035-11-08 08:00+02','group','active',gen_random_uuid(),null,null,null,null),
 ('41000000-0000-0000-0000-000000000187','11000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000182','00000000-0000-0000-0000-000000000181','2035-11-09 07:00+02','2035-11-09 08:00+02','individual','active',gen_random_uuid(),null,null,null,null);

select is((select hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000181',60)),2500::bigint,'Normál booking központi sávos díjat kap');
select is((select rate_source::text from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000182',0)),'training_room','A Tréningterem csoportos booking alapdíjforrást kap');
select is((select hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000183',60)),3200::bigint,'A user egyedi óradíja felülírja a központi díjat');
select is((select rate_source::text||':'||hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000184',0)),'booking_override:4100','A booking óradíj felülírja a user és Tréningterem díját');
select is((select rate_source::text||':'||hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000186',0)),'user_override:3200','A user óradíj felülírja a Tréningterem csoportos alapdíját');
select is((select rate_source::text||':'||hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000187',60)),'central_tier:2500','A Tréningterem egyéni használata normál központi díjazású');

select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000182','2035-10-01')),2500::bigint,'A havi elszámolás központi óradíjjal számol');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000183','2035-10-01')),5000::bigint,'A havi elszámolás Tréningterem alapdíjjal számol');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000184','2035-10-01')),3200::bigint,'A havi elszámolás user egyedi óradíjjal számol');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000185','2035-10-01')),4100::bigint,'A havi elszámolás tényleges booking óradíjjal számol');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select throws_ok(
  $$select public.admin_set_user_hourly_rate('00000000-0000-0000-0000-000000000182',3000,timezone('Europe/Budapest',now())::date+1,'Tiltott',gen_random_uuid())$$,
  '42501','Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.','Normál user nem módosíthat user óradíjat'
);
select throws_ok(
  $$update public.bookings set hourly_rate_override_huf=999 where id='41000000-0000-0000-0000-000000000181'$$,
  '42501',null,'Normál user közvetlenül sem módosíthat booking árat'
);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select lives_ok(
  $$select public.admin_set_user_hourly_rate('00000000-0000-0000-0000-000000000183',3300,timezone('Europe/Budapest',now())::date+1,'Jövőbeli teszt tarifa','42000000-0000-0000-0000-000000000181')$$,
  'Admin auditált jövőbeli user óradíjat állíthat be'
);
select lives_ok(
  $$select public.admin_set_booking_hourly_rate_override('41000000-0000-0000-0000-000000000183',3600,'Egyedi booking teszt','42000000-0000-0000-0000-000000000182')$$,
  'Admin egyetlen jövőbeli booking óradíját auditáltan felülírhatja'
);
select lives_ok(
  $$select public.admin_set_booking_hourly_rate_override('41000000-0000-0000-0000-000000000183',3600,'Javított booking indok','42000000-0000-0000-0000-000000000187')$$,
  'Admin az óradíj változtatása nélkül is auditáltan javíthatja a felülírás indokát'
);
select is((select hourly_rate_override_reason from public.bookings where id='41000000-0000-0000-0000-000000000183'),'Javított booking indok','Az indokjavítás megmarad a bookingon');
select is((select count(*) from public.audit_logs where action='pricing.booking_hourly_rate_override_set' and correlation_id='42000000-0000-0000-0000-000000000187' and before_data->>'hourly_rate_override_huf'='3600' and after_data->>'hourly_rate_override_huf'='3600' and before_data->>'reason'='Egyedi booking teszt' and after_data->>'reason'='Javított booking indok' and reason='Javított booking indok'),1::bigint,'Az indokjavítás régi és új indoka változatlan óradíj mellett auditált');
select lives_ok(
  $$select public.admin_set_booking_hourly_rate_override('41000000-0000-0000-0000-000000000183',3600,null,'42000000-0000-0000-0000-000000000188')$$,
  'Azonos ár és hiányzó új indok kompatibilis no-op, amely nem törli a meglévő indokot'
);
select is((select hourly_rate_override_reason from public.bookings where id='41000000-0000-0000-0000-000000000183'),'Javított booking indok','Általános booking-szerkesztés megőrzi a meglévő felülírás indokát');
select is((select count(*) from public.audit_logs where correlation_id='42000000-0000-0000-0000-000000000188'),0::bigint,'A kompatibilis no-op nem hoz létre félrevezető pénzügyi auditot');
select lives_ok(
  $$select public.admin_create_booking_with_pricing(
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000182',
    '2035-12-10 07:00+01','2035-12-10 08:00+01','individual',null,
    '42000000-0000-0000-0000-000000000185','Atomikus díjteszt',3700,'Admin booking egyedi díj'
  )$$,
  'Az admin booking és foglalásszintű díj egy tranzakcióban létrehozható'
);
select throws_ok(
  $$select public.admin_create_booking_with_pricing(
    '11000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000182',
    '2035-12-11 07:00+01','2035-12-11 08:00+01','individual',null,
    '42000000-0000-0000-0000-000000000186','Rollback díjteszt',3800,' '
  )$$,
  '22004','A díjmódosítás indoka kötelező.',
  'Hibás díjfelülírás az egész admin booking műveletet visszagörgeti'
);
reset role;
select is((select count(*) from public.audit_logs where action='pricing.user_hourly_rate_set' and correlation_id='42000000-0000-0000-0000-000000000181'),1::bigint,'A user díjmódosítás ki/mikor/miről/mire auditot hoz létre');
select is((select hourly_rate_override_huf from public.bookings where idempotency_key='42000000-0000-0000-0000-000000000185'),3700::bigint,'Az atomikusan létrehozott booking megőrzi a foglalásszintű díjat');
select is((select count(*) from public.bookings where idempotency_key='42000000-0000-0000-0000-000000000186'),0::bigint,'Sikertelen díjfelülírás után nem marad részleges booking');

-- A későbbi tarifa-időszak nem módosítja a korábbi szolgáltatási dátum feloldását.
update public.pricing_tiers set valid_to='2039-12-31' where valid_from='2026-10-01';
insert into public.pricing_tiers(min_minutes,max_minutes,hourly_rate_huf,valid_from) values
 (60,900,9999,'2040-01-01'),(901,3600,9998,'2040-01-01'),(3601,null,9997,'2040-01-01');
select is((select hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000181',60)),2500::bigint,'Későbbi tarifaváltozás nem írja át a korábbi booking alkalmazott szabályát');

-- Immutable revision snapshot: egy későbbi, indokolt revision sem írja át az elsőt.
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason) values
 ('41000000-0000-0000-0000-000000000185','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000185','00000000-0000-0000-0000-000000000181','2026-08-05 07:00+02','2026-08-05 08:00+02','individual','active',gen_random_uuid(),4300,'00000000-0000-0000-0000-000000000181',now(),'Snapshot teszt');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select lives_ok($$select * from public.admin_create_monthly_settlement_revision('00000000-0000-0000-0000-000000000185','2026-08-01','Első végleges számítás','42000000-0000-0000-0000-000000000183')$$,'A múltbeli havi elszámolás első revisionje elkészíthető');
reset role;
select is((select line.hourly_rate_huf from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id where line.booking_id='41000000-0000-0000-0000-000000000185' and revision.revision_number=1),4300::bigint,'Az első settlement revision a tényleges alkalmazott óradíjat snapshotolja');
select throws_ok($$update public.settlement_booking_lines set hourly_rate_huf=1 where booking_id='41000000-0000-0000-0000-000000000185'$$,'42501','A megőrzött elszámolási snapshot nem módosítható.','A történeti settlement sor változtathatatlan');
select throws_ok($$delete from public.settlement_booking_lines where booking_id='41000000-0000-0000-0000-000000000185'$$,'42501','A megőrzött elszámolási snapshot nem módosítható.','A történeti settlement sor nem törölhető');
update public.bookings set hourly_rate_override_huf=4400,updated_at=clock_timestamp() where id='41000000-0000-0000-0000-000000000185';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select lives_ok($$select * from public.admin_create_monthly_settlement_revision('00000000-0000-0000-0000-000000000185','2026-08-01','Indokolt korrekció','42000000-0000-0000-0000-000000000184')$$,'Indokolt korrekció új revisionként elkészíthető');
reset role;
select is((select string_agg(line.hourly_rate_huf::text,',' order by revision.revision_number) from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id where line.booking_id='41000000-0000-0000-0000-000000000185'),'4300,4400','Az új revision megőrzi az első snapshotot és külön tárolja a korrekciót');

-- A legutóbbi immutable revision marad az admin képernyő és export hiteles
-- forrása akkor is, ha az eredeti booking élő állapota később megváltozik.
update public.bookings set status='cancelled',hourly_rate_override_huf=4500,updated_at=clock_timestamp()
where id='41000000-0000-0000-0000-000000000185';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is((select count(*) from public.admin_monthly_pricing_summary('2026-08-01') where user_id='00000000-0000-0000-0000-000000000185'),1::bigint,'A snapshot user az élő booking későbbi módosítása után is szerepel az admin összesítésben');
select is((select pricing_state||':'||revision_number::text||':'||calculated_due_huf::text from public.admin_monthly_pricing_summary('2026-08-01') where user_id='00000000-0000-0000-0000-000000000185'),'snapshot:2:4400','Az admin összesítés a legutóbbi immutable revision pénzügyi értékét adja');
select is((select pricing_state||':'||revision_number::text||':'||hourly_rate_huf::text||':'||amount_huf::text from public.admin_monthly_pricing_details('2026-08-01','00000000-0000-0000-0000-000000000185') where booking_id='41000000-0000-0000-0000-000000000185'),'snapshot:2:4400:4400','A tételes admin exportforrás is a legutóbbi immutable revisiont adja');
reset role;

select is((select count(*) from public.audit_logs where action='pricing.booking_hourly_rate_override_set' and correlation_id='42000000-0000-0000-0000-000000000182' and before_data ? 'hourly_rate_override_huf' and after_data ? 'hourly_rate_override_huf'),1::bigint,'A booking ármódosítás ki/mikor/miről/mire auditot hoz létre');
select ok(not has_function_privilege('authenticated','public.calculate_monthly_pricing(uuid,date)','EXECUTE'),'A belső pénzügyi kalkulátor közvetlenül nem hívható authenticated szereppel');
select ok((select bool_and(prosecdef and coalesce(proconfig @> array['search_path=""'],false)) from pg_proc where oid in ('public.admin_set_central_pricing(date,bigint,bigint,bigint,text,uuid)'::regprocedure,'public.admin_set_user_hourly_rate(uuid,bigint,date,text,uuid)'::regprocedure,'public.admin_set_booking_hourly_rate_override(uuid,bigint,text,uuid)'::regprocedure)),'A kritikus admin ár-RPC-k SECURITY DEFINER és fix search_path beállításúak');

select * from finish();
rollback;
