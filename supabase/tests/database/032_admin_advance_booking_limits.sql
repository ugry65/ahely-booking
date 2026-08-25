begin;

select plan(10);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000321','limit-admin@example.invalid','{"first_name":"Limit","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000322','limit-user@example.invalid','{"first_name":"Limit","last_name":"User"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000321';

select is((select (value #>> '{}')::integer from public.app_settings where key='default_advance_booking_days'),90,'A normál default induló értéke 90 nap');
select is((select (value #>> '{}')::integer from public.app_settings where key='training_room_advance_days'),10,'A Tréningterem default induló értéke 10 nap');
select ok(not has_table_privilege('authenticated','public.app_settings','UPDATE'),'Authenticated nem írhatja közvetlenül az app_settings táblát');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000322',true);
select throws_ok(
  $$select public.admin_set_advance_booking_limits(120,14,'32000000-0000-0000-0000-000000000001'::uuid)$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem módosíthatja a limiteket RPC-n keresztül sem'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000321',true);
select lives_ok(
  $$select public.admin_set_advance_booking_limits(120,14,'32000000-0000-0000-0000-000000000002'::uuid)$$,
  'Admin módosíthatja mindkét előrefoglalási limitet'
);
reset role;

select is((select (value #>> '{}')::integer from public.app_settings where key='default_advance_booking_days'),120,'A normál limit 120 napra változott');
select is((select (value #>> '{}')::integer from public.app_settings where key='training_room_advance_days'),14,'A Tréningterem limit 14 napra változott');
select is((select count(*)::bigint from public.audit_logs where correlation_id='32000000-0000-0000-0000-000000000002'),1::bigint,'A módosítás pontosan egyszer auditált');
select is((select before_data->>'default_advance_booking_days' from public.audit_logs where correlation_id='32000000-0000-0000-0000-000000000002'),'90','Az audit megőrzi a korábbi normál limitet');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000321',true);
select throws_ok(
  $$select public.admin_set_advance_booking_limits(-1,10,'32000000-0000-0000-0000-000000000003'::uuid)$$,
  '22023',
  'Az előrefoglalási limitek csak nemnegatív egész napértékek lehetnek.',
  'Negatív limit elutasított'
);
reset role;

select * from finish();
rollback;
