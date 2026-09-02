begin;

select plan(20);

insert into auth.users (id, email, raw_user_meta_data) values
  ('82000000-0000-0000-0000-000000000001', 'pricing82@example.com', '{"first_name":"Pricing","last_name":"Test"}'),
  ('82000000-0000-0000-0000-000000000002', 'pricing82-boundary@example.com', '{"first_name":"Boundary","last_name":"Test"}');

-- Alapeset: 20 aktív normál óra. Az auth trigger automatikusan létrehozza a profilokat.
insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
select
  '11000000-0000-0000-0000-000000000002',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  ('2026-08-' || lpad(g::text,2,'0') || ' 08:00 Europe/Budapest')::timestamptz,
  ('2026-08-' || lpad(g::text,2,'0') || ' 10:00 Europe/Budapest')::timestamptz,
  'individual','active',gen_random_uuid()
from generate_series(1,10) g;

select is((select normal_minutes from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),1200,'20 óra elszámolandó');
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),38000::bigint,'20 óra sávos = 38 000 Ft');

insert into public.user_pricing_policies(user_id,pricing_scheme,valid_from,created_by)
values ('82000000-0000-0000-0000-000000000001','progressive','2026-08-01','82000000-0000-0000-0000-000000000001');
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),50000::bigint,'20 óra progresszív = 50 000 Ft');

update public.user_pricing_policies set pricing_scheme='free' where user_id='82000000-0000-0000-0000-000000000001';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),0::bigint,'Free normál foglalások = 0 Ft');

insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ('11000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','2026-08-20 08:00 Europe/Budapest','2026-08-20 10:00 Europe/Budapest','group','active',gen_random_uuid());
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),0::bigint,'Free Tréningterem csoportos foglalás is 0 Ft');

update public.user_pricing_policies set pricing_scheme='tiered' where user_id='82000000-0000-0000-0000-000000000001';
select is((select special_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),10000::bigint,'Nem-Free Tréningterem csoportos 2 óra = 10 000 Ft');

insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ('11000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001','2026-08-21 08:00 Europe/Budapest','2026-08-21 10:00 Europe/Budapest','individual','cancelled',gen_random_uuid());
select is((select normal_minutes from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),1200,'Törölt foglalás nem növeli az óraszámot');
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),48000::bigint,'Törölt foglalás nem növeli a fizetendőt');

insert into public.user_price_overrides(user_id,hourly_rate_huf,valid_from,reason,created_by)
values ('82000000-0000-0000-0000-000000000001',2400,'2026-08-01','teszt','82000000-0000-0000-0000-000000000001');
select is((select normal_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),48000::bigint,'Egyedi fix user-díj felülírja a normál sávot');

update public.user_pricing_policies set pricing_scheme='free' where user_id='82000000-0000-0000-0000-000000000001';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000001','2026-08-01')),0::bigint,'Free felülírja az egyedi fix és speciális díjat is');

-- Sávhatár-regressziók külön userrel és külön szobában.
-- 15 óra = 5 x 3 óra.
insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
select '11000000-0000-0000-0000-000000000003','82000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002',
  ('2026-08-' || lpad(g::text,2,'0') || ' 12:00 Europe/Budapest')::timestamptz,
  ('2026-08-' || lpad(g::text,2,'0') || ' 15:00 Europe/Budapest')::timestamptz,
  'individual','active',gen_random_uuid()
from generate_series(1,5) g;

select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),40500::bigint,'15 óra sávos = 40 500 Ft');
insert into public.user_pricing_policies(user_id,pricing_scheme,valid_from,created_by)
values ('82000000-0000-0000-0000-000000000002','progressive','2026-08-01','82000000-0000-0000-0000-000000000002');
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),40500::bigint,'15 óra progresszív = 40 500 Ft');

-- +5 óra = 20 óra.
insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key) values
('11000000-0000-0000-0000-000000000003','82000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002','2026-08-06 12:00 Europe/Budapest','2026-08-06 14:30 Europe/Budapest','individual','active',gen_random_uuid()),
('11000000-0000-0000-0000-000000000003','82000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002','2026-08-07 12:00 Europe/Budapest','2026-08-07 14:30 Europe/Budapest','individual','active',gen_random_uuid());
update public.user_pricing_policies set pricing_scheme='tiered' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),38000::bigint,'20 óra sávos határ felett = 38 000 Ft');
update public.user_pricing_policies set pricing_scheme='progressive' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),50000::bigint,'20 óra progresszív = 50 000 Ft');

-- +40 óra = 60 óra, más napszakban, ugyanabban a szobában.
insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
select '11000000-0000-0000-0000-000000000003','82000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002',
  ('2026-08-' || lpad(g::text,2,'0') || ' 17:00 Europe/Budapest')::timestamptz,
  ('2026-08-' || lpad(g::text,2,'0') || ' 19:00 Europe/Budapest')::timestamptz,
  'individual','active',gen_random_uuid()
from generate_series(1,20) g;
update public.user_pricing_policies set pricing_scheme='tiered' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),114000::bigint,'60 óra sávos = 114 000 Ft');
update public.user_pricing_policies set pricing_scheme='progressive' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),126000::bigint,'60 óra progresszív = 126 000 Ft');

-- +1 óra = 61 óra.
insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ('11000000-0000-0000-0000-000000000003','82000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002','2026-08-21 17:00 Europe/Budapest','2026-08-21 18:00 Europe/Budapest','individual','active',gen_random_uuid());
update public.user_pricing_policies set pricing_scheme='tiered' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),103700::bigint,'61 óra sávos = 103 700 Ft');
update public.user_pricing_policies set pricing_scheme='progressive' where user_id='82000000-0000-0000-0000-000000000002';
select is((select calculated_due_huf from public.calculate_monthly_pricing('82000000-0000-0000-0000-000000000002','2026-08-01')),127700::bigint,'61 óra progresszív = 127 700 Ft');

select ok(not has_function_privilege('authenticated', 'public.calculate_monthly_pricing(uuid,date)', 'EXECUTE'),'A belső számító közvetlenül nem hívható authenticated szerepkörből');
select ok(has_function_privilege('authenticated', 'public.admin_calculate_monthly_pricing(uuid,date)', 'EXECUTE'),'Az admin wrapper RPC elérhető authenticated szerepkörnek, belső admin ellenőrzéssel');

select * from finish();
rollback;
