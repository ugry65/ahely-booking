begin;

-- The filename preserves test history; #295 replaces the future-only policy
-- with current-open-month retroactivity. All fixture writes roll back.
select no_plan();
select set_config('test.pricing_month',date_trunc('month',timezone('Europe/Budapest',now()))::date::text,true);
select set_config('test.pricing_previous_month',(date_trunc('month',timezone('Europe/Budapest',now()))-interval '1 month')::date::text,true);
select set_config('test.pricing_next_month',(date_trunc('month',timezone('Europe/Budapest',now()))+interval '1 month')::date::text,true);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000194','pricing-guard-admin@example.invalid','{"first_name":"Pricing","last_name":"Guard"}'),
 ('00000000-0000-0000-0000-000000000320','open-price-normal@example.invalid','{"first_name":"Open","last_name":"Normal"}'),
 ('00000000-0000-0000-0000-000000000321','open-price-training@example.invalid','{"first_name":"Open","last_name":"Training"}'),
 ('00000000-0000-0000-0000-000000000322','open-price-fixed@example.invalid','{"first_name":"Open","last_name":"Fixed"}'),
 ('00000000-0000-0000-0000-000000000323','open-price-booking@example.invalid','{"first_name":"Open","last_name":"Booking"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000194';

insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
select id::uuid,room_id::uuid,user_id::uuid,'00000000-0000-0000-0000-000000000194',
  (month_value::date + starts::time) at time zone 'Europe/Budapest',
  (month_value::date + ends::time) at time zone 'Europe/Budapest',
  use_type::public.booking_use_type,'active',gen_random_uuid()
from (values
 ('41000000-0000-0000-0000-000000000320','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000320',current_setting('test.pricing_month'),'07:00','08:00','individual'),
 ('41000000-0000-0000-0000-000000000321','11000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000321',current_setting('test.pricing_month'),'07:00','08:00','group'),
 ('41000000-0000-0000-0000-000000000322','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000322',current_setting('test.pricing_month'),'08:00','09:00','individual'),
 ('41000000-0000-0000-0000-000000000323','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000323',current_setting('test.pricing_month'),'09:00','10:00','individual'),
 ('41000000-0000-0000-0000-000000000324','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000320',current_setting('test.pricing_previous_month'),'07:00','08:00','individual')
) v(id,room_id,user_id,month_value,starts,ends,use_type);

insert into public.user_price_overrides(user_id,hourly_rate_huf,valid_from,reason,created_by)
values ('00000000-0000-0000-0000-000000000322',4400,current_setting('test.pricing_month')::date,'Egyedi díj teszt','00000000-0000-0000-0000-000000000194');
update public.bookings set hourly_rate_override_huf=4300,
  hourly_rate_override_set_by='00000000-0000-0000-0000-000000000194',hourly_rate_override_set_at=now(),hourly_rate_override_reason='Booking díj teszt'
where id='41000000-0000-0000-0000-000000000323';

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',true);

select lives_ok(
  $$select * from public.admin_close_monthly_settlement_period(current_setting('test.pricing_previous_month')::date)$$,
  'A korábbi hónap valódi RPC-vel lezárható a regresszió előtt'
);
reset role;
select set_config('test.pricing_old_snapshot',(
  select md5(string_agg(to_jsonb(line)::text,'|' order by line.id))
  from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id
  join public.monthly_settlements settlement on settlement.id=revision.settlement_id
  where settlement.settlement_month=current_setting('test.pricing_previous_month')::date
),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',true);

select throws_ok(
  $$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date-1,3200,2200,1800,'Túl régi kezdés',gen_random_uuid())$$,
  '22023','Az új központi díjszabás legkorábban az aktuális hónap első napjától lehet érvényes.','Előző hónap központi díja nem módosítható'
);

select throws_ok(
  $$select public.admin_set_training_room_rate(6200,current_setting('test.pricing_month')::date-1,'Túl régi kezdés',gen_random_uuid())$$,
  '22023','Az új Tréningterem-díj legkorábban az aktuális hónap első napjától lehet érvényes.','Előző hónap Tréningterem-díja nem módosítható'
);

select throws_ok($$select public.admin_set_central_pricing(null,3200,2200,1800,'Hiányos',gen_random_uuid())$$,'22023',null,'Hiányzó kezdődátum elutasítva');
select throws_ok($$select public.admin_set_central_pricing('infinity',3200,2200,1800,'Végtelen',gen_random_uuid())$$,'22023',null,'Végtelen kezdődátum elutasítva');
select throws_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date,null,2200,1800,'Hiányos díj',gen_random_uuid())$$,'22023',null,'Hiányzó díj részleges tarifa nélkül elutasítva');
select throws_ok($$select public.admin_set_training_room_rate(-1,current_setting('test.pricing_month')::date,'Negatív',gen_random_uuid())$$,'22023',null,'Negatív díj elutasítva');
select throws_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date,3200,2200,1800,' ',gen_random_uuid())$$,'22004',null,'Indok nélküli módosítás elutasítva');

select lives_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_next_month')::date,3500,2300,1900,'Jövőbeli ütemezés',gen_random_uuid())$$,'Jövőbeli központi ütemezés megmarad');
select lives_ok($$select public.admin_set_training_room_rate(6500,current_setting('test.pricing_next_month')::date,'Jövőbeli ütemezés',gen_random_uuid())$$,'Jövőbeli Tréningterem-ütemezés megmarad');
select lives_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date,3200,2200,1800,'Nyitott hónap új díja','42000000-0000-0000-0000-000000000320')$$,'Nyitott hónap első napjától központi díj beállítható');
select lives_ok($$select public.admin_set_training_room_rate(6200,current_setting('test.pricing_month')::date,'Nyitott hónap új díja','42000000-0000-0000-0000-000000000321')$$,'Nyitott hónap első napjától Tréningterem-díj beállítható');
reset role;

select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000320',current_setting('test.pricing_month')::date)),3200::bigint,'A hónap eleji normál foglalás élő díja újraszámolódik');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000321',current_setting('test.pricing_month')::date)),6200::bigint,'A hónap eleji csoportos foglalás újraszámolódik');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000322',current_setting('test.pricing_month')::date)),4400::bigint,'A user egyedi díja megőrzi elsőbbségét');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000323',current_setting('test.pricing_month')::date)),4300::bigint,'A booking egyedi díja megőrzi elsőbbségét');
select is((select count(*) from public.audit_logs where correlation_id='42000000-0000-0000-0000-000000000320' and before_data is not null and after_data is not null and actor_user_id='00000000-0000-0000-0000-000000000194'),1::bigint,'A retroaktív központi változás teljes admin audittal rendelkezik');
select is((select count(*) from public.audit_logs where correlation_id='42000000-0000-0000-0000-000000000321' and before_data is not null and after_data is not null),1::bigint,'A retroaktív Tréningterem-változás auditált');
select is((select hourly_rate_huf from public.pricing_tiers where valid_from=current_setting('test.pricing_next_month')::date and min_minutes=60),3500::bigint,'A későbbi tarifát nem írja felül a hónap eleji módosítás');
select is((select valid_to from public.pricing_tiers where valid_from=current_setting('test.pricing_month')::date and min_minutes=60),current_setting('test.pricing_next_month')::date-1,'Nincs átfedés a későbbi tarifával');
select is((select md5(string_agg(to_jsonb(line)::text,'|' order by line.id)) from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id join public.monthly_settlements settlement on settlement.id=revision.settlement_id where settlement.settlement_month=current_setting('test.pricing_previous_month')::date),current_setting('test.pricing_old_snapshot'),'A korábbi lezárt pénzügyi sorok byte-szinten változatlanok');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000320',true);
select throws_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date,1,1,1,'Nem admin',gen_random_uuid())$$,'42501',null,'Normál user nem módosíthat központi tarifát');
select throws_ok($$select public.admin_set_training_room_rate(1,current_setting('test.pricing_month')::date,'Nem admin',gen_random_uuid())$$,'42501',null,'Normál user nem módosíthat Tréningterem-tarifát');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',true);
select lives_ok($$select public.admin_set_central_pricing(timezone('Europe/Budapest',now())::date,3200,2200,1800,'Mai kezdés',gen_random_uuid())$$,'Mai kezdődátum is megadható');
select lives_ok($$select * from public.admin_close_monthly_settlement_period(current_setting('test.pricing_month')::date)$$,'A módosított hónap az új díjjal valódi RPC-vel lezárható');
reset role;
select set_config('test.pricing_closed_snapshot',(
  select md5(string_agg(to_jsonb(line)::text,'|' order by line.id))
  from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id
  join public.monthly_settlements settlement on settlement.id=revision.settlement_id
  where settlement.settlement_month=current_setting('test.pricing_month')::date
),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000194',true);
select throws_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_month')::date,1,1,1,'Lezárt átírás','42000000-0000-0000-0000-000000000322')$$,'22023','Lezárt hónap központi díjszabása nem módosítható.','Lezárás után a havi központi díj módosítása tiltott');
select throws_ok($$select public.admin_set_training_room_rate(1,current_setting('test.pricing_month')::date,'Lezárt átírás','42000000-0000-0000-0000-000000000323')$$,'22023','Lezárt hónap Tréningterem-díja nem módosítható.','Lezárás után a Tréningterem díj módosítása tiltott');
select lives_ok($$select public.admin_set_central_pricing(current_setting('test.pricing_next_month')::date,3500,2300,1900,'Következő hónap',gen_random_uuid())$$,'Lezárt aktuális hónap után a következő hónap továbbra is szerkeszthető');
reset role;
select is((select count(*) from public.audit_logs where correlation_id in ('42000000-0000-0000-0000-000000000322','42000000-0000-0000-0000-000000000323')),0::bigint,'Tiltott módosítás nem hagy részleges auditot');
select is((select md5(string_agg(to_jsonb(line)::text,'|' order by line.id)) from public.settlement_booking_lines line join public.settlement_revisions revision on revision.id=line.settlement_revision_id join public.monthly_settlements settlement on settlement.id=revision.settlement_id where settlement.settlement_month=current_setting('test.pricing_month')::date),current_setting('test.pricing_closed_snapshot'),'A lezárt aktuális hónap snapshotja a tiltott változtatások után változatlan');
select ok(not has_function_privilege('anon','public.admin_set_central_pricing(date,bigint,bigint,bigint,text,uuid)','EXECUTE'),'Anon nem hívhat központi díjírást');
select ok(not has_function_privilege('anon','public.admin_set_training_room_rate(bigint,date,text,uuid)','EXECUTE'),'Anon nem hívhat Tréningterem-díjírást');

select * from finish();
rollback;
