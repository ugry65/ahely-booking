begin;

select plan(13);

select has_table('public', 'profiles', 'A profiles tábla létezik');
select has_table('public', 'rooms', 'A rooms tábla létezik');
select has_table('public', 'bookings', 'A bookings tábla létezik');
select has_table('public', 'settlement_revisions', 'A settlement_revisions tábla létezik');

select has_column('public', 'bookings', 'time_range', 'A foglalási időtartomány tárolt oszlopként létezik');

select ok(
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'bookings'
      and c.conname = 'bookings_no_room_overlap'
      and c.contype = 'x'
  ),
  'A dupla foglalást tiltó exclusion constraint létezik'
);

select has_trigger(
  'public',
  'audit_logs',
  'audit_logs_immutable',
  'Az auditnapló módosítását tiltó trigger létezik'
);

select has_trigger(
  'public',
  'bookings',
  'bookings_no_physical_delete',
  'A foglalások fizikai törlését tiltó trigger létezik'
);

select has_trigger(
  'public',
  'payments',
  'payments_no_physical_delete',
  'A befizetések fizikai törlését tiltó trigger létezik'
);

select has_trigger(
  'public',
  'settlement_booking_lines',
  'settlement_booking_lines_no_physical_delete',
  'Az elszámolási sorok fizikai törlését tiltó trigger létezik'
);

select is(
  (
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and not c.relrowsecurity
  ),
  0::bigint,
  'Minden public tábla RLS-védett'
);

select is(
  (select value from public.app_settings where key = 'timezone'),
  '"Europe/Budapest"'::jsonb,
  'Az alkalmazás időzónája Europe/Budapest'
);

select is(
  (select count(*)::bigint from public.rooms where is_active),
  11::bigint,
  'A seed pontosan 11 aktív induló helyiséget hoz létre'
);

select * from finish();
rollback;
