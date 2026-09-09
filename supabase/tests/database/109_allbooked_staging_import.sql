begin;

select plan(18);

select has_table('public', 'allbooked_migration_bookings', 'Az AllBooked ujjlenyomat-ledger létezik');
select is((select relrowsecurity from pg_class where oid = 'public.allbooked_migration_bookings'::regclass), true, 'A ledger RLS-védett');
select ok(not has_table_privilege('authenticated', 'public.allbooked_migration_bookings', 'SELECT'), 'Az authenticated nem olvashatja a ledgert');
select ok(not has_function_privilege('authenticated', 'public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid)', 'EXECUTE'), 'Az authenticated nem hívhatja az importot');
select ok(has_function_privilege('service_role', 'public.admin_import_papp_dalma_allbooked(uuid,uuid,text,jsonb,uuid)', 'EXECUTE'), 'Csak a szerveroldali service role kap importjogot');

insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000109', 'migration-admin@example.invalid', '{"first_name":"Migration","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000110', 'pappdalma17@gmail.com', '{"first_name":"Dalma","last_name":"Papp","must_change_password":true}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000109';

update public.bookings
set status = 'cancelled'
where room_id = (select id from public.rooms where name = 'Forrás tér')
  and (start_at at time zone 'Europe/Budapest')::date between date '2026-09-03' and date '2026-09-17';

create temp table allbooked_payload(data jsonb);
insert into allbooked_payload(data)
select jsonb_agg(jsonb_build_object(
  'sourceFingerprint', encode(digest('papp-dalma-' || item.i::text, 'sha256'), 'hex'),
  'startAt', item.start_at,
  'endAt', item.start_at + make_interval(mins => item.duration_minutes),
  'durationMinutes', item.duration_minutes
) order by item.i)
from (
  select i,
    timestamptz '2026-09-03 06:00:00+00' + make_interval(days => i - 1) as start_at,
    60 as duration_minutes
  from generate_series(1, 15) i
  union all
  select i,
    timestamptz '2026-09-03 08:00:00+00' + make_interval(days => i - 16) as start_at,
    60 as duration_minutes
  from generate_series(16, 19) i
  union all
  select 20, timestamptz '2026-09-07 08:00:00+00', 90
  union all
  select 21, timestamptz '2026-09-08 08:00:00+00', 90
) item;
grant select on allbooked_payload to service_role;

set local role service_role;
select lives_ok(
  $$select public.admin_import_papp_dalma_allbooked(
    '00000000-0000-0000-0000-000000000109',
    '00000000-0000-0000-0000-000000000110',
    '+36307337981',
    (select data from pg_temp.allbooked_payload),
    '10900000-0000-0000-0000-000000000001'
  )$$,
  'A jóváhagyott 21/21 minta egy tranzakcióban importálható'
);
reset role;

select is((select count(*) from public.bookings where user_id = '00000000-0000-0000-0000-000000000110'), 21::bigint, 'Pontosan 21 foglalás jött létre');
select is((select count(*) from public.allbooked_migration_bookings where user_id = '00000000-0000-0000-0000-000000000110'), 21::bigint, 'Mind a 21 ujjlenyomat bekerült a ledgerbe');
select is(
  (select concat_ws('|', first_name, last_name, email, phone, role::text, is_active::text) from public.profiles where id = '00000000-0000-0000-0000-000000000110'),
  'Dalma|Papp|pappdalma17@gmail.com|+36307337981|user|true',
  'A profil és a normalizált elérhetőség pontos'
);
select is(
  (select count(*) from public.access_group_members member join public.access_groups group_row on group_row.id = member.group_id where member.user_id = '00000000-0000-0000-0000-000000000110' and group_row.name = 'Forrás tér'),
  1::bigint,
  'A Forrás legacy tag a Forrás tér csoportjogot adja'
);
select is(
  (select count(*) filter (where extract(epoch from (end_at - start_at)) / 60 = 60)::text || '|' || count(*) filter (where extract(epoch from (end_at - start_at)) / 60 = 90)::text || '|' || sum(extract(epoch from (end_at - start_at)) / 60)::integer::text from public.bookings where user_id = '00000000-0000-0000-0000-000000000110'),
  '19|2|1320',
  'A 19x60 + 2x90 perc és 1320 perc összesen pontos'
);
select is(
  (select count(*) from public.user_price_overrides where user_id = '00000000-0000-0000-0000-000000000110')
  + (select count(*) from public.monthly_settlements where user_id = '00000000-0000-0000-0000-000000000110'),
  0::bigint,
  'Legacy ár és payment/settlement nem jött létre'
);
select is((select count(*) from public.audit_logs where action = 'allbooked.booking_imported' and correlation_id = '10900000-0000-0000-0000-000000000001'), 21::bigint, 'Mind a 21 foglalás auditált');

set local role service_role;
select lives_ok(
  $$select public.admin_import_papp_dalma_allbooked(
    '00000000-0000-0000-0000-000000000109',
    '00000000-0000-0000-0000-000000000110',
    '+36307337981',
    (select data from pg_temp.allbooked_payload),
    '10900000-0000-0000-0000-000000000002'
  )$$,
  'Az azonos forrás idempotens újrafuttatása sikeres'
);
reset role;

select is((select count(*) from public.bookings where user_id = '00000000-0000-0000-0000-000000000110'), 21::bigint, 'Az újrafuttatás nem duplikál foglalást');
select is((select count(*) from public.audit_logs where action = 'allbooked.booking_imported'), 21::bigint, 'Az újrafuttatás nem duplikál import auditot');

set local role service_role;
select throws_ok(
  $$select public.admin_import_papp_dalma_allbooked(
    '00000000-0000-0000-0000-000000000109',
    '00000000-0000-0000-0000-000000000110',
    '+36307337981',
    ((select data from pg_temp.allbooked_payload) || '[{"legacyPrice":1700}]'::jsonb),
    '10900000-0000-0000-0000-000000000003'
  )$$,
  '22023',
  'Pontosan 21 foglalás importálható.',
  'A plusz legacy pénzügyi payload fail-closed módon elutasított'
);
reset role;

select is((select count(*) from public.bookings where user_id = '00000000-0000-0000-0000-000000000110'), 21::bigint, 'A hibás próbálkozás után sem marad részleges adat');

select * from finish();
rollback;
