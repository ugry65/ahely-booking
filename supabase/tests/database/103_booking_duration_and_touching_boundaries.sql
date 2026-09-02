begin;

select plan(5);

insert into auth.users (id, email, raw_user_meta_data) values (
  'c0000000-0000-0000-0000-000000000103',
  'uat-booking-boundary@example.invalid',
  '{"first_name":"UAT","last_name":"Boundary"}'
);

insert into public.user_room_permissions(user_id, room_id, can_book) values (
  'c0000000-0000-0000-0000-000000000103',
  '11000000-0000-0000-0000-000000000002',
  true
)
on conflict (user_id, room_id) do update set can_book = true;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000103', true);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      'c0000000-0000-0000-0000-000000000103',
      %L::timestamptz,
      %L::timestamptz,
      'individual',
      'UAT 90 perc',
      'c1000000-0000-0000-0000-000000000103'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 15) + time '10:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 15) + time '11:30') at time zone 'Europe/Budapest'
  ),
  'UAT-BOOK-02: 90 perces, 30 perces rácshoz igazodó foglalás létrehozható'
);

reset role;

select is(
  (
    select extract(epoch from (end_at - start_at))::integer / 60
    from public.bookings
    where idempotency_key = 'c1000000-0000-0000-0000-000000000103'
  ),
  90,
  'UAT-BOOK-02: a mentett foglalás időtartama pontosan 90 perc'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c0000000-0000-0000-0000-000000000103', true);

select lives_ok(
  format(
    $sql$select public.create_booking(
      '11000000-0000-0000-0000-000000000002',
      'c0000000-0000-0000-0000-000000000103',
      %L::timestamptz,
      %L::timestamptz,
      'individual',
      'UAT érintkező',
      'c1000000-0000-0000-0000-000000000104'
    )$sql$,
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 15) + time '11:30') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 15) + time '12:30') at time zone 'Europe/Budapest'
  ),
  'UAT-BOOK-09: az első foglalás végével pontosan érintkező következő foglalás létrehozható'
);

reset role;

select is(
  (
    select count(*)
    from public.bookings
    where user_id = 'c0000000-0000-0000-0000-000000000103'
      and room_id = '11000000-0000-0000-0000-000000000002'
      and idempotency_key in (
        'c1000000-0000-0000-0000-000000000103',
        'c1000000-0000-0000-0000-000000000104'
      )
  ),
  2::bigint,
  'UAT-BOOK-09: mindkét egymáshoz érő foglalás pontosan egyszer megmarad'
);

select ok(
  (
    select first_booking.end_at = second_booking.start_at
    from public.bookings first_booking
    join public.bookings second_booking
      on second_booking.idempotency_key = 'c1000000-0000-0000-0000-000000000104'
    where first_booking.idempotency_key = 'c1000000-0000-0000-0000-000000000103'
  ),
  'UAT-BOOK-09: a két foglalás határa valóban azonos, nincs mesterséges rés közöttük'
);

select * from finish();
rollback;
