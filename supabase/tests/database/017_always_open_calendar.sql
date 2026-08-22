begin;

select plan(3);

select hasnt_table(
  'public',
  'calendar_exceptions',
  'A globális zárt napokat tároló tábla megszűnt'
);

select ok(
  position('calendar_exceptions' in pg_get_functiondef('public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure)) = 0,
  'A közös validátor nem használ naptári zárva tartási kivételt'
);

select ok(
  position('opening_time' in pg_get_functiondef('public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure)) > 0,
  'A közös validátor a minden napra érvényes napi idősávot használja'
);

select * from finish();
rollback;
