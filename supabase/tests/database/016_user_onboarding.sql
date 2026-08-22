begin;

select plan(10);

select has_function('public', 'complete_own_onboarding', array['text','text','text','text','text','text','text','text','uuid'], 'Az onboarding RPC létezik');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000161', 'onboarding-private@example.invalid', '{"first_name":"Anna","last_name":"Teszt"}'),
  ('00000000-0000-0000-0000-000000000162', 'onboarding-business@example.invalid', '{"first_name":"Béla","last_name":"Cég"}');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000161', true);
select throws_ok(
  $$select public.complete_own_onboarding('', 'private', 'Teszt Anna', '1181', 'Budapest', 'Fő utca', '1', '', gen_random_uuid())$$,
  'P0001', 'A telefonszám megadása kötelező.',
  'Telefonszám nélkül az onboarding elutasított'
);
select throws_ok(
  $$select public.complete_own_onboarding('+361234567', 'private', '', '1181', 'Budapest', 'Fő utca', '1', '', gen_random_uuid())$$,
  'P0001', 'A számlázási név megadása kötelező.',
  'Számlázási név nélkül az onboarding elutasított'
);
select lives_ok(
  $$select public.complete_own_onboarding('+361234567', 'private', 'Teszt Anna', '1181', 'Budapest', 'Fő utca', '1', '', '26000000-0000-0000-0000-000000000161')$$,
  'Magánszemély teljes adatokkal befejezheti az onboardingot'
);
reset role;
select is((select billing_name from public.profiles where id='00000000-0000-0000-0000-000000000161'), 'Teszt Anna', 'A számlázási név mentve van');
select ok((select onboarding_completed_at is not null from public.profiles where id='00000000-0000-0000-0000-000000000161'), 'Az onboarding lezárási időpontja mentve van');
select is((select count(*) from public.audit_logs where correlation_id='26000000-0000-0000-0000-000000000161'), 1::bigint, 'Az onboarding auditált');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000162', true);
select throws_ok(
  $$select public.complete_own_onboarding('+361111111', 'business', 'Cég Béla Kft.', '1181', 'Budapest', 'Cég utca', '2', '', gen_random_uuid())$$,
  'P0001', 'Vállalkozói számlázás esetén az adószám megadása kötelező.',
  'Vállalkozói számlázás adószám nélkül elutasított'
);
select lives_ok(
  $$select public.complete_own_onboarding('+361111111', 'business', 'Cég Béla Kft.', '1181', 'Budapest', 'Cég utca', '2', '12345678-1-42', '26000000-0000-0000-0000-000000000162')$$,
  'Vállalkozói számlázás adószámmal menthető'
);
reset role;
select is((select tax_number from public.profiles where id='00000000-0000-0000-0000-000000000162'), '12345678-1-42', 'A vállalkozói adószám mentve van');

select * from finish();
rollback;
