begin;

select plan(4);

insert into auth.users (id, email, raw_user_meta_data) values
  ('83000000-0000-0000-0000-000000000001', 'pricing-admin@example.com', '{"first_name":"Admin","last_name":"Pricing"}'::jsonb),
  ('83000000-0000-0000-0000-000000000002', 'pricing-user@example.com', '{"first_name":"User","last_name":"Pricing"}'::jsonb);

update public.profiles set role = 'admin' where id = '83000000-0000-0000-0000-000000000001';

insert into public.bookings (room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values (
  '11000000-0000-0000-0000-000000000002',
  '83000000-0000-0000-0000-000000000002',
  '83000000-0000-0000-0000-000000000002',
  '2026-08-10 08:00 Europe/Budapest',
  '2026-08-10 10:00 Europe/Budapest',
  'individual','active',gen_random_uuid()
);

select set_config('request.jwt.claim.sub', '83000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select * from public.admin_monthly_pricing_summary(date '2026-08-01')$$,
  '42501',
  'Nincs jogosultság a havi díjazási összesítőhöz.',
  'Normál user nem olvashatja mások pénzügyi összesítőjét'
);

select set_config('request.jwt.claim.sub', '83000000-0000-0000-0000-000000000001', true);
select is(
  (select count(*) from public.admin_monthly_pricing_summary(date '2026-08-01') where user_id='83000000-0000-0000-0000-000000000002'),
  1::bigint,
  'Admin látja az aktív foglalással rendelkező user havi díjazási sorát'
);
select is(
  (select calculated_due_huf from public.admin_monthly_pricing_summary(date '2026-08-01') where user_id='83000000-0000-0000-0000-000000000002'),
  5400::bigint,
  'A dashboard read model ugyanazt a központi díjszámítást adja vissza'
);
select is(
  (select total_minutes from public.admin_monthly_pricing_summary(date '2026-08-01') where user_id='83000000-0000-0000-0000-000000000002'),
  120,
  'A dashboard read model az aktív havi perceket adja vissza'
);

select * from finish();
rollback;
