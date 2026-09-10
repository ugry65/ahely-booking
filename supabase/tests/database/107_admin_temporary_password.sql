begin;

select plan(10);

select has_function(
  'public',
  'admin_require_password_change',
  array['uuid', 'uuid'],
  'Az ideiglenes jelszó kötelező cseréjét előkészítő RPC létezik'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_require_password_change(uuid, uuid)', 'EXECUTE'),
  'Az authenticated szerepkör meghívhatja az RPC-t'
);
select ok(
  not has_function_privilege('anon', 'public.admin_require_password_change(uuid, uuid)', 'EXECUTE'),
  'Az anon szerepkör nem hívhatja meg az RPC-t'
);

insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000107', 'password-admin@example.invalid', '{"first_name":"Password","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000108', 'password-user@example.invalid', '{"first_name":"Password","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000109', 'password-inactive@example.invalid', '{"first_name":"Password","last_name":"Inactive"}'),
  ('00000000-0000-0000-0000-000000000110', 'password-nonadmin@example.invalid', '{"first_name":"Password","last_name":"Nonadmin"}');

update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000107';
update public.profiles set is_active = false where id = '00000000-0000-0000-0000-000000000109';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000107', true);
select lives_ok(
  $$select public.admin_require_password_change('00000000-0000-0000-0000-000000000108', '10700000-0000-0000-0000-000000000001')$$,
  'Aktív admin aktív usernél előírhat kötelező jelszócserét'
);
reset role;

select is(
  (select must_change_password from public.profiles where id = '00000000-0000-0000-0000-000000000108'),
  true,
  'A kötelező jelszócsere jelző bekapcsolt'
);
select is(
  (select count(*) from public.audit_logs where correlation_id = '10700000-0000-0000-0000-000000000001'),
  1::bigint,
  'A művelet pontosan egyszer auditált'
);
select is(
  (select after_data from public.audit_logs where correlation_id = '10700000-0000-0000-0000-000000000001'),
  '{"must_change_password": true}'::jsonb,
  'Az audit kizárólag a kötelező jelszócsere állapotát tartalmazza'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000107', true);
select throws_ok(
  $$select public.admin_require_password_change('00000000-0000-0000-0000-000000000109', gen_random_uuid())$$,
  'P0001',
  'Inaktív felhasználónak nem állítható be ideiglenes jelszó.',
  'Inaktív usernél a művelet elutasított'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000110', true);
select throws_ok(
  $$select public.admin_require_password_change('00000000-0000-0000-0000-000000000108', gen_random_uuid())$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem írhat elő jelszócserét'
);
reset role;

select ok(
  not has_function_privilege('public', 'public.admin_require_password_change(uuid, uuid)', 'EXECUTE'),
  'A PUBLIC nem hívhatja meg az RPC-t'
);

select * from finish();
rollback;
