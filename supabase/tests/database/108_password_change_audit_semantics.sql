begin;

select plan(8);

insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000111', 'initial-change@example.invalid', '{"first_name":"Initial","last_name":"Change","must_change_password":true}'),
  ('00000000-0000-0000-0000-000000000112', 'normal-reset@example.invalid', '{"first_name":"Normal","last_name":"Reset"}');

select is(
  (select must_change_password from public.profiles where id = '00000000-0000-0000-0000-000000000111'),
  true,
  'A kötelező első jelszócsere jelző a tesztusernél aktív'
);
select is(
  (select must_change_password from public.profiles where id = '00000000-0000-0000-0000-000000000112'),
  false,
  'A normál recovery usernél nincs kötelező első jelszócsere'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000111', true);
select lives_ok(
  $$select public.complete_own_password_change('10800000-0000-0000-0000-000000000001')$$,
  'A kötelező jelszócsere lezárható'
);
reset role;

select is(
  (select must_change_password from public.profiles where id = '00000000-0000-0000-0000-000000000111'),
  false,
  'A kötelező jelszócsere jelző kikapcsolt'
);
select is(
  (select count(*) from public.audit_logs where correlation_id = '10800000-0000-0000-0000-000000000001'),
  1::bigint,
  'A valódi első jelszócsere pontosan egyszer auditált'
);
select is(
  (select after_data from public.audit_logs where correlation_id = '10800000-0000-0000-0000-000000000001'),
  '{"must_change_password": false}'::jsonb,
  'Az audit csak a kötelező jelszócsere állapotváltozását tartalmazza'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000112', true);
select lives_ok(
  $$select public.complete_own_password_change('10800000-0000-0000-0000-000000000002')$$,
  'A normál recovery utáni lezáró hívás biztonságos no-op'
);
reset role;

select is(
  (select count(*) from public.audit_logs where correlation_id = '10800000-0000-0000-0000-000000000002'),
  0::bigint,
  'A normál recovery nem kap félrevezető initial_password_changed auditot'
);

select * from finish();
rollback;
