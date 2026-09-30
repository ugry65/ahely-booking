begin;

select plan(4);

-- 22:30 UTC is already 00:30 on 1 April after Budapest's spring DST jump.
-- The date is fixed and independent of the test runner's clock or SQL timezone.
insert into auth.users(id,email,raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000283','dst-settlement@example.invalid',
   '{"first_name":"DST","last_name":"Settlement"}');
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values ('41000000-0000-0000-0000-000000000283',
  '11000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000283',
  '00000000-0000-0000-0000-000000000283',
  '2026-03-31 22:30:00+00','2026-03-31 23:30:00+00',
  'individual','active',gen_random_uuid());

select is(public.monthly_settlement_cutoff_blockers('2026-04-01',
  '2026-03-30 22:29:00+00'::timestamptz),1::bigint,
  'A már áprilisi budapesti foglalás az áprilisi zárás cutoffját blokkolja');
select is(public.monthly_settlement_cutoff_blockers('2026-03-01',
  '2026-03-30 22:29:00+00'::timestamptz),0::bigint,
  'A még márciusi UTC dátum nem sorolja a foglalást márciushoz');
select is((select normal_minutes from public.calculate_monthly_pricing(
  '00000000-0000-0000-0000-000000000283','2026-04-01')),60,
  'A tényleges pénzügyi kalkuláció az áprilisi snapshothoz sorolja a 60 percet');
select is((select normal_minutes from public.calculate_monthly_pricing(
  '00000000-0000-0000-0000-000000000283','2026-03-01')),0,
  'A márciusi pénzügyi kalkuláció nem számolja el az áprilisi budapesti alkalmat');

select * from finish();
rollback;
