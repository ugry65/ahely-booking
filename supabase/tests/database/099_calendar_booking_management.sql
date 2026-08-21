begin;

select plan(16);

select has_function('public', 'update_booking_scope', array['uuid','text','timestamp with time zone','uuid','timestamp with time zone','timestamp with time zone','booking_use_type','text','uuid'], 'Scoped update RPC exists');
select has_function('public', 'cancel_booking_scope', array['uuid','text','text','uuid'], 'Scoped cancel RPC exists');
select ok(has_function_privilege('authenticated', 'public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid)', 'EXECUTE'), 'Authenticated can call scoped update');
select ok(has_function_privilege('authenticated', 'public.cancel_booking_scope(uuid,text,text,uuid)', 'EXECUTE'), 'Authenticated can call scoped cancel');

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000171', 'calendar-manage-user@example.invalid', '{"first_name":"Calendar","last_name":"Manager"}'),
  ('00000000-0000-0000-0000-000000000172', 'calendar-other-user@example.invalid', '{"first_name":"Calendar","last_name":"Other"}'),
  ('00000000-0000-0000-0000-000000000173', 'calendar-admin@example.invalid', '{"first_name":"Calendar","last_name":"Admin"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000173';
insert into public.user_room_permissions(user_id, room_id, can_book, can_repeat) values
  ('00000000-0000-0000-0000-000000000171','11000000-0000-0000-0000-000000000002',true,true),
  ('00000000-0000-0000-0000-000000000171','11000000-0000-0000-0000-000000000001',true,true),
  ('00000000-0000-0000-0000-000000000172','11000000-0000-0000-0000-000000000002',true,true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000171', true);
select lives_ok(
  format($sql$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000171',
    %L::timestamptz,%L::timestamptz,'daily',null,4,'{}'::date[],'abort_all','individual','kezelési teszt',
    '29000000-0000-0000-0000-000000000171')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest'),
  'Test series can be created');
reset role;

select is((select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171')), 4::bigint, 'Series has four bookings');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000171', true);
select lives_ok(
  format($sql$select public.update_booking_scope(
    %L::uuid,'following',%L::timestamptz,'11000000-0000-0000-0000-000000000002',
    %L::timestamptz,%L::timestamptz,'individual','módosított sorozat','29000000-0000-0000-0000-000000000172')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') order by start_at offset 1 limit 1),
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') order by start_at offset 1 limit 1),
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 4) + time '11:00') at time zone 'Europe/Budapest'),
  'Following scope update succeeds');
reset role;

select is((select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and (start_at at time zone 'Europe/Budapest')::time = time '09:00'), 1::bigint, 'First occurrence stays unchanged');
select is((select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and (start_at at time zone 'Europe/Budapest')::time = time '10:00'), 3::bigint, 'Selected and following occurrences move together');
select is((select count(*) from public.audit_logs where correlation_id='29000000-0000-0000-0000-000000000172'), 4::bigint, 'Scoped update writes per-booking plus series audit');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000172', true);
select throws_ok(
  format($sql$select public.cancel_booking_scope(%L::uuid,'occurrence',null,'29000000-0000-0000-0000-000000000173')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') order by start_at limit 1)),
  'P0001', 'Csak a saját foglalásodat mondhatod le.', 'Other user cannot cancel booking');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000171', true);
select lives_ok(
  format($sql$select public.cancel_booking_scope(%L::uuid,'occurrence','egy alkalom','29000000-0000-0000-0000-000000000174')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and status='active' order by start_at offset 1 limit 1)),
  'Single occurrence cancel succeeds');
reset role;
select is((select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and status='cancelled'), 1::bigint, 'Exactly one occurrence is cancelled');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000171', true);
select lives_ok(
  format($sql$select public.cancel_booking_scope(%L::uuid,'series','teljes sorozat','29000000-0000-0000-0000-000000000175')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and status='active' order by start_at limit 1)),
  'Full future series cancel succeeds');
reset role;
select is((select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='29000000-0000-0000-0000-000000000171') and status='active'), 0::bigint, 'No active future occurrence remains');
select is((select count(*) from public.booking_scope_operations where actor_user_id='00000000-0000-0000-0000-000000000171'), 3::bigint, 'Series scope operations are persisted');

select * from finish();
rollback;
