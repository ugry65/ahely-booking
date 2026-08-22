begin;

select plan(11);

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000191','repeat-limit-user@example.invalid','{"first_name":"Limit","last_name":"User"}'),
 ('00000000-0000-0000-0000-000000000192','repeat-limit-admin@example.invalid','{"first_name":"Limit","last_name":"Admin"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000192';

-- Legacy TRUE intentionally exercises the supported compatibility RPC. Direct
-- authenticated writes to user_room_permissions are not part of the API contract.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select public.admin_set_user_room_permission(
  '00000000-0000-0000-0000-000000000191',
  '11000000-0000-0000-0000-000000000002',
  true, true, '19100000-0000-0000-0000-000000000011'
);
select public.admin_set_user_room_permission(
  '00000000-0000-0000-0000-000000000191',
  '11000000-0000-0000-0000-000000000001',
  true, true, '19100000-0000-0000-0000-000000000012'
);
reset role;

select is(
  (select can_repeat_bookings from public.profiles where id='00000000-0000-0000-0000-000000000191'),
  true,
  'A legacy repeat grant RPC a user-szintű repeat jogot bekapcsolja'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'weekly',null,2,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000001')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 70) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 70) + time '10:00') at time zone 'Europe/Budapest'
  ),
  'Normál user 90 napon belüli normál helyiség-sorozata létrejön'
);

select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'weekly',null,2,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000002')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 84) + time '11:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 84) + time '12:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  null,
  'Normál user sorozata elutasított, ha egy későbbi alkalom túllépi a 90 napos limitet'
);
reset role;

select is(
  (select count(*)::bigint from public.booking_series where idempotency_key='19100000-0000-0000-0000-000000000002'),
  0::bigint,
  'A 90 napot túllépő abort_all sorozat atomian visszagördül'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000191',true);
select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'weekly',null,2,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000003')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '13:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '14:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.',
  'Normál user Tréningteremben user-szintű repeat joggal sem hozhat létre sorozatot'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'weekly',null,4,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000004')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 84) + time '15:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 84) + time '16:00') at time zone 'Europe/Budapest'
  ),
  'Admin hosszú normál szobás sorozata túlnyúlhat a normál 90 napos limiten'
);

select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'weekly',null,2,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000005')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '17:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '18:00') at time zone 'Europe/Budapest'
  ),
  'Admin Tréningterem-sorozata a normál 10 napos limit után is létrejön'
);
reset role;

select is(
  (select count(*)::bigint from public.bookings where series_id=(select id from public.booking_series where idempotency_key='19100000-0000-0000-0000-000000000004')),
  4::bigint,
  'Az admin 90 napon túli sorozatának minden alkalma létrejön'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000192',true);
select lives_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'monthly',null,13,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000006')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 1) + time '07:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 1) + time '08:00') at time zone 'Europe/Budapest'
  ),
  'Admin darabszámos havi sorozata létrejön, ha az utolsó alkalom 366 napon belül marad'
);

select throws_ok(
  format(
    $sql$select public.create_booking_series(
      '11000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000191',
      %L::timestamptz,%L::timestamptz,'monthly',null,14,'{}','abort_all','individual',null,
      '19100000-0000-0000-0000-000000000007')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 1) + time '08:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 1) + time '09:00') at time zone 'Europe/Budapest'
  ),
  'P0001',
  'A sorozat utolsó alkalma legfeljebb 366 nappal lehet az első alkalom után.',
  'Admin darabszámos sorozata sem nyúlhat 366 napon túl'
);
reset role;

select is(
  (select count(*)::bigint from public.booking_series where idempotency_key='19100000-0000-0000-0000-000000000007'),
  0::bigint,
  'A 366 napot túllépő darabszámos sorozatból sem sorozatrekord nem marad'
);

select * from finish();
rollback;
