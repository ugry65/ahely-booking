begin;

select plan(7);
select has_column('public','bookings','booking_title','A foglalás opcionális címe tárolható');
select has_column('public','booking_series','booking_title','A sorozat címe is tárolható');
select ok(position('char_length(booking_title) <= 100' in pg_get_constraintdef((select oid from pg_constraint where conname='bookings_title_length'))) > 0,'A booking title adatbázisban is legfeljebb 100 karakter');
select ok(
  position('booking_title' in pg_get_functiondef('public.list_calendar_bookings(timestamp with time zone,timestamp with time zone)'::regprocedure)) > 0,
  'A publikus naptár read model tartalmazza a privacy-szűrt címmezőt; a tulajdonos/admin viselkedést a 020_booking_title_visibility.sql ellenőrzi'
);
select ok(position('booking_title' in pg_get_functiondef('public.list_my_bookings()'::regprocedure)) > 0,'A saját foglalások read model tartalmazza a címet');
select ok(position('booking_title' in pg_get_functiondef('public.list_calendar_booking_management(timestamp with time zone,timestamp with time zone)'::regprocedure)) > 0,'A jogosultságszűrt management read model tartalmazza a címet');
select has_function('public','claim_booking_title_request',array['uuid','text','text'],'A title idempotencia külön backend ellenőrzést kap');
select * from finish();
rollback;
