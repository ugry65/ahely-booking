begin;

select plan(8);

insert into auth.users (id, email, raw_user_meta_data) values
  ('90000000-0000-0000-0000-000000000001', 'fixed-admin@example.com', '{"first_name":"Fix","last_name":"Admin"}'::jsonb),
  ('90000000-0000-0000-0000-000000000002', 'fixed-user@example.com', '{"first_name":"Fix","last_name":"User"}'::jsonb),
  ('90000000-0000-0000-0000-000000000003', 'fixed-normal@example.com', '{"first_name":"Normal","last_name":"User"}'::jsonb);

update public.profiles set role = 'admin' where id = '90000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.admin_set_user_pricing_configuration(
    '90000000-0000-0000-0000-000000000002', 'fixed', 2200, date '2027-01-01', gen_random_uuid()
  )$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem állíthat Fix óradíjat'
);

select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '90000000-0000-0000-0000-000000000002', 'fixed', 2200, date '2027-01-01', '90000000-0000-0000-0000-000000000010'
  )$$,
  'Admin be tud állítani Fix óradíjat'
);

select is(
  (select hourly_rate_huf from public.user_price_overrides
    where user_id = '90000000-0000-0000-0000-000000000002'
      and date '2027-01-01' between valid_from and coalesce(valid_to, 'infinity'::date)
    order by valid_from desc limit 1),
  2200::bigint,
  'A Fix óradíj effektív 2027 januárban'
);

insert into public.bookings (
  room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key
) values (
  '11000000-0000-0000-0000-000000000002',
  '90000000-0000-0000-0000-000000000002',
  '90000000-0000-0000-0000-000000000001',
  '2027-01-12 10:00 Europe/Budapest',
  '2027-01-12 12:00 Europe/Budapest',
  'individual','active',gen_random_uuid()
);

select is(
  (select normal_due_huf from public.calculate_monthly_pricing(
    '90000000-0000-0000-0000-000000000002', date '2027-01-01'
  )),
  4400::bigint,
  'A havi motor a Fix 2200 Ft-os óradíjat használja a normál órákra'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '90000000-0000-0000-0000-000000000002', 'free', null, date '2027-02-01', '90000000-0000-0000-0000-000000000011'
  )$$,
  'Admin későbbi hónaptól Free módra válthat'
);

select is(
  (select valid_to from public.user_price_overrides
    where user_id = '90000000-0000-0000-0000-000000000002'
      and valid_from = date '2027-01-01'),
  date '2027-01-31',
  'Nem-Fix módra váltás lezárja az effektív Fix időszakot'
);

select is(
  public.effective_user_pricing_scheme('90000000-0000-0000-0000-000000000002', date '2027-02-01'),
  'free'::public.user_pricing_scheme,
  'Free policy februártól effektív'
);

select ok(
  (select count(*) >= 2 from public.audit_logs
    where entity_id = '90000000-0000-0000-0000-000000000002'
      and action in ('user_price_override.set','user_price_override.close','user_pricing_policy.set')),
  'A Fix beállítás és lezárás auditált'
);

select * from finish();
rollback;
