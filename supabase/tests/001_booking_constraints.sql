begin;

select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  (
    '00000000-0000-0000-0000-000000000001',
    'admin@example.invalid',
    '{"first_name":"Teszt","last_name":"Admin"}'
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'user@example.invalid',
    '{"first_name":"Teszt","last_name":"User"}'
  );

update public.profiles
set role = 'admin'
where id = '00000000-0000-0000-0000-000000000001';

insert into public.rooms (id, name, display_order) values
  ('10000000-0000-0000-0000-000000000001', 'Teszt szoba', 1);

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, idempotency_key
) values (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  '2026-09-01 08:00:00+02',
  '2026-09-01 09:00:00+02',
  '30000000-0000-0000-0000-000000000001'
);

select lives_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-01 09:00:00+02', '2026-09-01 10:00:00+02',
      '30000000-0000-0000-0000-000000000002'
    )$$,
  'Az egymást érintő foglalások nem ütköznek'
);

select throws_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-01 08:30:00+02', '2026-09-01 09:30:00+02',
      '30000000-0000-0000-0000-000000000003'
    )$$,
  '23P01',
  null,
  'Az átfedő aktív foglalást a DB elutasítja'
);

update public.bookings
set status = 'cancelled'
where id = '20000000-0000-0000-0000-000000000001';

select is(
  (
    select count(*)
    from public.bookings
    where id = '20000000-0000-0000-0000-000000000001'
      and status = 'cancelled'
  ),
  1::bigint,
  'A lemondott foglalás történeti sora megmarad'
);

select lives_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-01 08:00:00+02', '2026-09-01 09:00:00+02',
      '30000000-0000-0000-0000-000000000004'
    )$$,
  'A lemondott foglalás idősávja újra használható'
);

select throws_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-02 08:00:00+02', '2026-09-02 08:30:00+02',
      '30000000-0000-0000-0000-000000000005'
    )$$,
  '23514',
  null,
  'A minimum 60 perces szabály DB-szinten is él'
);

select throws_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-03 08:15:00+02', '2026-09-03 09:15:00+02',
      '30000000-0000-0000-0000-000000000006'
    )$$,
  '23514',
  null,
  'A nem félórás rácsra eső kezdés elutasított'
);

select throws_ok(
  $$insert into public.bookings (
      room_id, user_id, created_by, start_at, end_at, idempotency_key
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000001',
      '2026-09-03 10:00:00+02', '2026-09-03 11:15:00+02',
      '30000000-0000-0000-0000-000000000007'
    )$$,
  '23514',
  null,
  'A nem félórás rácsra eső befejezés elutasított'
);

insert into public.audit_logs (
  actor_user_id, action, entity_type, entity_id, correlation_id
) values (
  '00000000-0000-0000-0000-000000000001',
  'test',
  'booking',
  '20000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001'
);

select throws_ok(
  $$update public.audit_logs set action = 'tampered' where entity_id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  'audit_logs is append-only',
  'Az auditnapló módosítása tiltott'
);

select throws_ok(
  $$delete from public.audit_logs where entity_id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  'audit_logs is append-only',
  'Az auditnapló fizikai törlése tiltott'
);

select throws_ok(
  $$delete from public.bookings where id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  'physical delete is forbidden for bookings',
  'A foglalás fizikai törlése tiltott'
);

select * from finish();
rollback;
