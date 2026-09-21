begin;

select plan(35);

select has_table('public', 'booking_email_worker_runs', 'A worker heartbeat audit tábla létezik');
select has_function('public', 'start_booking_email_worker_run', array['text'], 'A worker futásindító RPC létezik');
select has_function(
  'public',
  'finish_booking_email_worker_run',
  array['uuid','text','integer','integer','integer','integer','integer','text','text'],
  'A worker futáslezáró RPC létezik'
);
select has_function('public', 'admin_booking_email_monitor', array[]::text[], 'Az admin monitor összesítő RPC létezik');
select has_function('public', 'admin_booking_email_problem_items', array['integer'], 'Az admin problémalista RPC létezik');
select has_function('public', 'admin_booking_email_worker_runs', array['integer'], 'Az admin heartbeat lista RPC létezik');
select has_trigger(
  'public',
  'booking_email_worker_runs',
  'booking_email_worker_runs_protected',
  'A worker-futásokat egyszer lezárható audit trigger védi'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.booking_email_worker_runs'::regclass),
  true,
  'A worker heartbeat tábla RLS-védett'
);
select ok(
  not has_table_privilege('authenticated', 'public.booking_email_worker_runs', 'SELECT'),
  'Az authenticated szerepkör közvetlenül nem olvashatja a worker auditot'
);
select ok(
  not has_table_privilege('service_role', 'public.booking_email_worker_runs', 'SELECT'),
  'A service_role is csak szűk RPC-n át kezeli a worker auditot'
);
select ok(
  not has_function_privilege('authenticated', 'public.start_booking_email_worker_run(text)', 'EXECUTE'),
  'Az authenticated szerepkör nem indíthat worker auditot'
);
select ok(
  has_function_privilege('service_role', 'public.start_booking_email_worker_run(text)', 'EXECUTE'),
  'A service_role indíthat worker auditot'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text)',
    'EXECUTE'
  ),
  'Az authenticated szerepkör nem zárhat worker auditot'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text)',
    'EXECUTE'
  ),
  'A service_role lezárhat worker auditot'
);
select ok(
  has_function_privilege('authenticated', 'public.admin_booking_email_monitor()', 'EXECUTE'),
  'Az authenticated szerepkör meghívhatja az admin ellenőrzésű monitort'
);
select is(
  (select proconfig from pg_proc where oid = 'public.start_booking_email_worker_run(text)'::regprocedure)
    @> array['search_path=""'],
  true,
  'A futásindító RPC rögzített üres search_pathot használ'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text)'::regprocedure
  ) @> array['search_path=""'],
  true,
  'A futáslezáró RPC rögzített üres search_pathot használ'
);
select ok(
  position('recipient' in pg_get_function_result('public.admin_booking_email_monitor()'::regprocedure)) = 0
  and position('payload' in pg_get_function_result('public.admin_booking_email_monitor()'::regprocedure)) = 0
  and position('provider_message_id' in pg_get_function_result('public.admin_booking_email_monitor()'::regprocedure)) = 0,
  'A monitor szerződése nem ad vissza címzettet, payloadot vagy provider Message-ID-t'
);

insert into auth.users (id, email, raw_user_meta_data) values
  (
    'a6000000-0000-0000-0000-000000000001',
    'monitor-admin@example.invalid',
    '{"first_name":"Monitor","last_name":"Admin"}'
  ),
  (
    'a6000000-0000-0000-0000-000000000002',
    'monitor-user@example.invalid',
    '{"first_name":"Monitor","last_name":"User"}'
  );

update public.profiles set role = 'admin' where id = 'a6000000-0000-0000-0000-000000000001';

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key
) values (
  'a6000000-0000-0000-0000-000000000010',
  '11000000-0000-0000-0000-000000000002',
  'a6000000-0000-0000-0000-000000000002',
  'a6000000-0000-0000-0000-000000000001',
  '2030-02-10 09:00 Europe/Budapest',
  '2030-02-10 10:00 Europe/Budapest',
  'individual',
  'active',
  'a6000000-0000-0000-0000-000000000011'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select * from public.admin_booking_email_monitor()$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem olvashatja az e-mail monitort'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.start_booking_email_worker_run('disabled')$$,
  '22023',
  'A worker mód csak capture vagy send lehet.',
  'Disabled módhoz nem hozható létre megtévesztő heartbeat'
);
select set_config(
  'test.email_success_run_id',
  public.start_booking_email_worker_run('capture')::text,
  true
);
select ok(
  current_setting('test.email_success_run_id')::uuid is not null,
  'A service role capture worker-futást indíthat'
);
select lives_ok(
  format(
    $$select public.finish_booking_email_worker_run(%L::uuid, 'success', 2, 0, 1, 1, 0, null, null)$$,
    current_setting('test.email_success_run_id')
  ),
  'A worker-futás konzisztens sikeres összesítővel lezárható'
);
reset role;
select is(
  (
    select status || ':' || claimed_count::text || ':' || captured_count::text || ':' || retry_count::text
    from public.booking_email_worker_runs
    where id = current_setting('test.email_success_run_id')::uuid
  ),
  'success:2:1:1',
  'A sikeres heartbeat pontos futásösszesítést őriz'
);
set local role service_role;
select throws_ok(
  format(
    $$select public.finish_booking_email_worker_run(%L::uuid, 'success', 0, 0, 0, 0, 0, null, null)$$,
    current_setting('test.email_success_run_id')
  ),
  '42501',
  'A worker-futás nem található vagy már lezárt.',
  'Egy worker-futás csak egyszer zárható le'
);

select set_config(
  'test.email_failed_run_id',
  public.start_booking_email_worker_run('send')::text,
  true
);
select lives_ok(
  format(
    $$select public.finish_booking_email_worker_run(
      %L::uuid, 'failed', 0, 0, 0, 0, 0, 'worker_failed', 'A worker futása nem fejeződött be.'
    )$$,
    current_setting('test.email_failed_run_id')
  ),
  'A worker-hiba biztonságos, nyers részlet nélküli állapotként lezárható'
);
reset role;

insert into public.booking_email_worker_runs (id, mode, started_at)
values (
  'a6000000-0000-0000-0000-000000000020',
  'capture',
  statement_timestamp() - interval '31 minutes'
);

select set_config(
  'test.email_due_id',
  public.enqueue_booking_email(
    'a6000000-0000-0000-0000-000000000101', 'booking.created', 'single',
    'a6000000-0000-0000-0000-000000000010', null,
    'a6000000-0000-0000-0000-000000000002', 'monitor-user@example.invalid',
    'a6000000-0000-0000-0000-000000000001', true, 1, '{"kind":"due"}'::jsonb
  )::text,
  true
);
update public.booking_email_outbox
set next_attempt_at = statement_timestamp() - interval '20 minutes'
where id = current_setting('test.email_due_id')::uuid;

select set_config(
  'test.email_retry_id',
  public.enqueue_booking_email(
    'a6000000-0000-0000-0000-000000000102', 'booking.updated', 'single',
    'a6000000-0000-0000-0000-000000000010', null,
    'a6000000-0000-0000-0000-000000000002', 'monitor-user@example.invalid',
    'a6000000-0000-0000-0000-000000000001', true, 1, '{"kind":"retry"}'::jsonb
  )::text,
  true
);
update public.booking_email_outbox
set status = 'retry', attempts = 1, next_attempt_at = statement_timestamp() - interval '5 minutes',
    last_error_code = 'smtp_timeout', last_error_safe = 'Átmeneti SMTP-hiba.'
where id = current_setting('test.email_retry_id')::uuid;

select set_config(
  'test.email_dead_id',
  public.enqueue_booking_email(
    'a6000000-0000-0000-0000-000000000103', 'booking.cancelled', 'single',
    'a6000000-0000-0000-0000-000000000010', null,
    'a6000000-0000-0000-0000-000000000002', 'monitor-user@example.invalid',
    'a6000000-0000-0000-0000-000000000001', true, 1, '{"kind":"dead"}'::jsonb
  )::text,
  true
);
update public.booking_email_outbox
set status = 'dead_letter', attempts = 3,
    last_error_code = 'smtp_auth', last_error_safe = 'Az SMTP hitelesítés sikertelen.'
where id = current_setting('test.email_dead_id')::uuid;

insert into public.booking_email_delivery_attempts (
  outbox_id, lease_token, attempt_number, outcome, error_code, error_safe, duration_ms
)
select
  current_setting('test.email_dead_id')::uuid,
  extensions.gen_random_uuid(),
  attempt_number,
  'dead_letter',
  'smtp_auth',
  'Az SMTP hitelesítés sikertelen.',
  10
from generate_series(1, 3) attempt_number;

select set_config(
  'test.email_stale_id',
  public.enqueue_booking_email(
    'a6000000-0000-0000-0000-000000000104', 'booking.updated', 'single',
    'a6000000-0000-0000-0000-000000000010', null,
    'a6000000-0000-0000-0000-000000000002', 'monitor-user@example.invalid',
    'a6000000-0000-0000-0000-000000000001', true, 1, '{"kind":"stale"}'::jsonb
  )::text,
  true
);
update public.booking_email_outbox
set status = 'sending', lease_token = extensions.gen_random_uuid(),
    leased_at = statement_timestamp() - interval '2 minutes',
    lease_expires_at = statement_timestamp() - interval '1 minute'
where id = current_setting('test.email_stale_id')::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000001', true);
select is(
  (
    select due_count::text || ':' || retry_count::text || ':' || dead_letter_count::text || ':'
      || stale_sending_count::text || ':' || stale_worker_run_count::text || ':' || smtp_auth_error_24h_count::text
    from public.admin_booking_email_monitor()
  ),
  '2:1:1:1:1:3',
  'Az admin monitor pontosan összesíti az esedékes, retry, dead-letter, stale és auth-hiba állapotokat'
);
select is(
  (
    select (
      oldest_due_at is not null
      and last_worker_started_at is not null
      and last_worker_success_at is not null
      and last_worker_failure_at is not null
      and database_now is not null
    )::text
    from public.admin_booking_email_monitor()
  ),
  'true',
  'A monitor az esedékességi és heartbeat időpontokat is visszaadja'
);
select is(
  (select count(*) from public.admin_booking_email_problem_items(50)),
  3::bigint,
  'A problémalista csak retry, dead-letter és lejárt lease rekordot ad'
);
select is(
  (
    select count(*)
    from public.admin_booking_email_problem_items(50)
    where last_error_safe like '%@%'
      or last_error_code like '%@%'
  ),
  0::bigint,
  'A problémalista biztonságos hibamezőiben nincs címzett e-mail'
);
select is(
  (select count(*) from public.admin_booking_email_worker_runs(20)),
  3::bigint,
  'Az admin heartbeat lista minden teszt worker-futást megmutat'
);
select is(
  (
    select count(*) filter (where status = 'success')::text || ':'
      || count(*) filter (where status = 'failed')::text || ':'
      || count(*) filter (where status = 'running')::text
    from public.admin_booking_email_worker_runs(20)
  ),
  '1:1:1',
  'A heartbeat lista elkülöníti a sikeres, hibás és beragadt futást'
);
select throws_ok(
  $$select * from public.admin_booking_email_problem_items(0)$$,
  '22023',
  'A monitor lista mérete 1 és 100 közötti lehet.',
  'Az admin problémalista korlátozza a lekért elemszámot'
);
reset role;

select throws_ok(
  format(
    $$update public.booking_email_worker_runs set error_safe = 'átírva' where id = %L::uuid$$,
    current_setting('test.email_success_run_id')
  ),
  '42501',
  'booking_email_worker_runs can only be completed once',
  'A lezárt worker audit nem írható át'
);
select throws_ok(
  format(
    $$delete from public.booking_email_worker_runs where id = %L::uuid$$,
    current_setting('test.email_success_run_id')
  ),
  '42501',
  'booking_email_worker_runs is append-only',
  'A worker audit fizikailag nem törölhető'
);
select throws_ok(
  $$update public.booking_email_worker_runs
    set started_at = statement_timestamp()
    where id = 'a6000000-0000-0000-0000-000000000020'$$,
  '42501',
  'booking_email_worker_runs identity is immutable',
  'A futó heartbeat kezdő időpontja sem módosítható'
);

select * from finish();
rollback;
