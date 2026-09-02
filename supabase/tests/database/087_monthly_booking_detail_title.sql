begin;

select plan(3);

insert into auth.users (id, email, raw_user_meta_data) values
  ('87000000-0000-0000-0000-000000000001', 'detail-title-admin@example.com', '{"first_name":"Admin","last_name":"Title"}'::jsonb),
  ('87000000-0000-0000-0000-000000000002', 'detail-title-user@example.com', '{"first_name":"User","last_name":"Title"}'::jsonb),
  ('87000000-0000-0000-0000-000000000003', 'detail-title-other@example.com', '{"first_name":"Other","last_name":"Title"}'::jsonb);

update public.profiles set role = 'admin' where id = '87000000-0000-0000-0000-000000000001';

insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,booking_title)
values (
  '11000000-0000-0000-0000-000000000001',
  '87000000-0000-0000-0000-000000000002',
  '87000000-0000-0000-0000-000000000001',
  '2026-11-23 10:00 Europe/Budapest',
  '2026-11-23 11:00 Europe/Budapest',
  'group','active',gen_random_uuid(),'Kovács család csoport'
), (
  '11000000-0000-0000-0000-000000000002',
  '87000000-0000-0000-0000-000000000003',
  '87000000-0000-0000-0000-000000000003',
  '2026-11-24 10:00 Europe/Budapest',
  '2026-11-24 11:00 Europe/Budapest',
  'individual','active',gen_random_uuid(),'Másik kliens'
);

select set_config('request.jwt.claim.sub', '87000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select * from public.admin_monthly_active_booking_details(date '2026-11-01', null)$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem olvashatja az admin tételes havi lekérdezést'
);

select set_config('request.jwt.claim.sub', '87000000-0000-0000-0000-000000000001', true);
select is(
  (select booking_title from public.admin_monthly_active_booking_details(date '2026-11-01', '87000000-0000-0000-0000-000000000002') limit 1),
  'Kovács család csoport'::text,
  'A tételes havi lekérdezés visszaadja a foglalás címét'
);

select is(
  (select count(*) from public.admin_monthly_active_booking_details(date '2026-11-01', '87000000-0000-0000-0000-000000000002')),
  1::bigint,
  'A user-szűrés csak a kiválasztott user aktív foglalásait adja vissza'
);

select * from finish();
rollback;
