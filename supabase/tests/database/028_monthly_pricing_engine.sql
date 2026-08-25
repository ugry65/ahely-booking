begin;

select plan(10);

insert into auth.users (id, email) values
  ('82000000-0000-0000-0000-000000000001', 'pricing82@example.com');
insert into public.profiles (id, first_name, last_name, email) values
  ('82000000-0000-0000-0000-000000000001', 'Pricing', 'Test', 'pricing82@example.com');

-- 20 active normal hours in August: tiered => all 20 hours at 1900 Ft.
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

select * from finish();
rollback;
