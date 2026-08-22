begin;

select plan(3);

select hasnt_table(
  'public',
  'calendar_exceptions',
  'A globális zárt napokat tároló tábla megszűnt'
);

select unlike(
  pg_get_functiondef('public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure),
  '%calendar_exceptions%',
  'A közös validátor nem használ naptári zárva tartási kivételt'
);

select like(
  pg_get_functiondef('public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure),
  '%opening_time%',
  'A közös validátor a minden napra érvényes napi idősávot használja'
);

select * from finish();
rollback;
