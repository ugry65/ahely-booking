begin;

select plan(3);

select ok(
  position('raise warning ''booking_email_bridge_failed sqlstate=%'', SQLSTATE;' in
    pg_get_functiondef('public.enqueue_booking_email_from_audit()'::regprocedure)) > 0,
  'A bridge biztonságos SQLSTATE figyelmeztetést ad a hibáról'
);
select ok(
  position('SQLERRM' in upper(pg_get_functiondef('public.enqueue_booking_email_from_audit()'::regprocedure))) = 0,
  'A bridge nem írhatja naplóba a hiba szövegét vagy érzékeny adatot'
);
select ok(
  position('return new;' in lower(pg_get_functiondef('public.enqueue_booking_email_from_audit()'::regprocedure))) > 0
  and (select tgdeferrable and tginitdeferred from pg_trigger
       where tgrelid = 'public.audit_logs'::regclass and tgname = 'booking_email_from_audit'),
  'A bridge megőrzi a deferred trigger és booking-hibaisoláció szerződését'
);

select * from finish();
rollback;
