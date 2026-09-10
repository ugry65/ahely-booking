begin;

select plan(21);

insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-000000000001', 'scope-admin@example.invalid', '{"first_name":"Scope","last_name":"Admin"}'),
  ('a0000000-0000-0000-0000-000000000002', 'scope-user@example.invalid', '{"first_name":"Scope","last_name":"User"}'),
  ('a0000000-0000-0000-0000-000000000003', 'scope-other@example.invalid', '{"first_name":"Scope","last_name":"Other"}');
update public.profiles set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000001';
update public.profiles set can_repeat_bookings = true where id = 'a0000000-0000-0000-0000-000000000002';
insert into public.user_room_permissions(user_id, room_id, can_book, can_repeat) values
  ('a0000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000002',true,true),
  ('a0000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000001',true,true)
on conflict (user_id, room_id) do update set can_book = true, can_repeat = true;

-- Ez a fájl a scope üzleti szemantikát teszteli. A security/EXECUTE/RLS határt
-- külön DB tesztek fedik. Itt a teszt-session privilegizált marad, miközben
-- az RPC actorát továbbra is a request.jwt.claim.sub határozza meg. Az ownership
-- határ viszont üzleti invariáns is, ezért arra itt explicit negatív regresszió van.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);

select lives_ok(
  format($sql$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',
    %L::timestamptz,%L::timestamptz,'daily',null,4,'{}'::date[],'abort_all','individual','scope alap',
    'a0000000-0000-0000-0000-000000000101')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '10:00') at time zone 'Europe/Budapest'),
  'Négy alkalmas normál sorozat létrehozható'
);

-- Másik normál user nem kezelheti a sorozat tulajdonosának scope-ját.
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
select throws_ok(
  format($sql$select public.update_booking_scope(
    %L::uuid,'series',%L::timestamptz,%L::uuid,%L::timestamptz,%L::timestamptz,
    'individual','tiltott módosítás','a0000000-0000-0000-0000-000000000105'
  )$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1),
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1),
    (select room_id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1),
    (select start_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1),
    (select end_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1)),
  'P0001',
  'Csak a saját foglalásodat módosíthatod.',
  'Más user sorozatának scope-update művelete elutasított'
);
select throws_ok(
  format($sql$select public.cancel_booking_scope(%L::uuid,'series','tiltott lemondás','a0000000-0000-0000-0000-000000000106')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at limit 1)),
  'P0001',
  'Csak a saját foglalásodat mondhatod le.',
  'Más user sorozatának scope-cancel művelete elutasított'
);
select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000002', true);

update public.bookings
set booking_title = 'Megőrzendő scope cím'
where series_id = (select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101');

select is(
  public.update_booking_scope(
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 1 limit 1),
    'occurrence',
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 1 limit 1),
    '11000000-0000-0000-0000-000000000002',
    (select start_at + interval '1 hour' from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 1 limit 1),
    (select end_at + interval '1 hour' from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 1 limit 1),
    'individual','occurrence módosítva','a0000000-0000-0000-0000-000000000102'
  ),
  1,
  'Occurrence update pontosan egy bookingot módosít'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and note='occurrence módosítva'),
  1::bigint,
  'Occurrence update csak a kiválasztott alkalmat érinti'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and booking_title='Megőrzendő scope cím'),
  4::bigint,
  'Scope update a booking_title mezőt nem írja felül'
);

select is(
  public.update_booking_scope(
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 2 limit 1),
    'series',
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 2 limit 1),
    '11000000-0000-0000-0000-000000000002',
    (select start_at + interval '2 hours' from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 2 limit 1),
    (select start_at + interval '3 hours' from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') order by start_at offset 2 limit 1),
    'individual','teljes jövő módosítva','a0000000-0000-0000-0000-000000000103'
  ),
  4,
  'Series update minden aktív jövőbeli bookingot módosít'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and note='teljes jövő módosítva'),
  4::bigint,
  'Series update minden jövőbeli targetre az új mezőket alkalmazza'
);

select is(
  public.cancel_booking_scope(
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and status='active' order by start_at offset 2 limit 1),
    'following','following teszt','a0000000-0000-0000-0000-000000000104'
  ),
  2,
  'Following cancel a kiválasztottat és minden későbbi aktív bookingot lemondja'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and status='cancelled'),
  2::bigint,
  'Following cancel után két booking cancelled'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000101') and status='active'),
  2::bigint,
  'Following cancel a korábbi két bookingot érintetlenül hagyja'
);

select lives_ok(
  format($sql$select public.create_booking_series(
    '11000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',
    %L::timestamptz,%L::timestamptz,'daily',null,2,'{}'::date[],'abort_all','individual','cutoff scope',
    'a0000000-0000-0000-0000-000000000111')$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 20) + time '10:00') at time zone 'Europe/Budapest'),
  'Cutoff tesztsorozat létrejön'
);
update public.app_settings set value='10000'::jsonb where key='cancellation_cutoff_hours';
select throws_ok(
  format($sql$select public.cancel_booking_scope(%L::uuid,'series','cutoff rollback','a0000000-0000-0000-0000-000000000112')$sql$,
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000111') order by start_at limit 1)),
  'P0001',
  'A sorozat egyik érintett foglalása 10000 órán belül kezdődik, ezért a művelet nem hajtható végre.',
  'Cutoffon belüli target miatt a teljes scope-cancel elutasított'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000111') and status='active'),
  2::bigint,
  'Cutoff hiba után egyik booking sem mondódott le'
);

select set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000001', true);
select lives_ok(
  format($sql$select public.admin_create_booking_series_with_group_rate(
    '11000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002',
    %L::timestamptz,%L::timestamptz,'daily',null,2,'{}','abort_all','group',
    'rate scope','a0000000-0000-0000-0000-000000000121','Rate scope cím',7500
  )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 30) + time '10:00') at time zone 'Europe/Budapest'),
  '7500 Ft-os Tréningterem csoportos sorozat létrejön'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') and group_hourly_rate_huf=7500),
  2::bigint,
  'A Tréningterem sorozat kezdetben bookingonként 7500 Ft-os rate-et tartalmaz'
);

select is(
  public.update_booking_scope(
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    'series',
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    '11000000-0000-0000-0000-000000000002',
    (select start_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    (select end_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    'individual','rate null','a0000000-0000-0000-0000-000000000123'
  ),
  2,
  'Normál/egyéni állapotra váltás mindkét targetet módosítja'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') and group_hourly_rate_huf is null),
  2::bigint,
  'Tréningterem+Csoportos státusz elhagyásakor a speciális rate nullázódik'
);

select is(
  public.update_booking_scope(
    (select id from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    'series',
    (select updated_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    '11000000-0000-0000-0000-000000000001',
    (select start_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    (select end_at from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') order by start_at limit 1),
    'group','rate default','a0000000-0000-0000-0000-000000000124'
  ),
  2,
  'Visszaváltás Tréningterem+Csoportos módra mindkét targetet módosítja'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') and group_hourly_rate_huf=5000),
  2::bigint,
  'Újra Tréningterem+Csoportos állapotnál a default 5000 Ft-os rate kerül alkalmazásra'
);
select is(
  (select count(*) from public.bookings where series_id=(select id from public.booking_series where idempotency_key='a0000000-0000-0000-0000-000000000121') and booking_title='Rate scope cím'),
  2::bigint,
  'Többszöri scope update után is megmarad a booking title'
);

select * from finish();
rollback;