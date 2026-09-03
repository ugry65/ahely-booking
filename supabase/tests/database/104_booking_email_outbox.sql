begin;

select plan(47);

select has_table('public', 'booking_email_outbox', 'A célzott booking e-mail outbox tábla létezik');
select has_table('public', 'booking_email_delivery_attempts', 'Az append-only kézbesítési napló létezik');
select has_function(
  'public',
  'enqueue_booking_email',
  array['uuid','text','text','uuid','uuid','uuid','text','uuid','boolean','integer','jsonb'],
  'A belső idempotens enqueue helper létezik'
);
select has_function(
  'public',
  'claim_booking_email_outbox',
  array['integer','integer'],
  'A lease-alapú worker claim RPC létezik'
);
select has_function(
  'public',
  'complete_booking_email_outbox',
  array['uuid','uuid','text','text','text','text','integer','timestamp with time zone'],
  'A lease-fenced eredményrögzítő RPC létezik'
);
select has_trigger(
  'public',
  'booking_email_outbox',
  'booking_email_outbox_protected',
  'Az outbox üzleti adatát és fizikai törlését trigger védi'
);
select has_trigger(
  'public',
  'booking_email_delivery_attempts',
  'booking_email_delivery_attempts_immutable',
  'A kézbesítési napló append-only triggerrel védett'
);

select is(
  (
    select count(*)::bigint
    from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in ('booking_email_outbox', 'booking_email_delivery_attempts')
      and relation.relrowsecurity
  ),
  2::bigint,
  'Mindkét új public tábla RLS-védett'
);
select ok(
  not has_table_privilege('authenticated', 'public.booking_email_outbox', 'SELECT'),
  'Az authenticated szerepkör közvetlenül nem olvashatja az outboxot'
);
select ok(
  not has_table_privilege('service_role', 'public.booking_email_outbox', 'SELECT'),
  'A service_role is csak szűk RPC-n át olvashatja az outboxot'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.enqueue_booking_email(uuid,text,text,uuid,uuid,uuid,text,uuid,boolean,integer,jsonb)',
    'EXECUTE'
  ),
  'Az authenticated szerepkör nem hívhatja a belső enqueue helpert'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.enqueue_booking_email(uuid,text,text,uuid,uuid,uuid,text,uuid,boolean,integer,jsonb)',
    'EXECUTE'
  ),
  'A service_role sem kerülheti meg a kanonikus booking RPC-ket enqueue-val'
);
select ok(
  not has_function_privilege('authenticated', 'public.claim_booking_email_outbox(integer,integer)', 'EXECUTE'),
  'Az authenticated szerepkör nem claimelhet e-mailt'
);
select ok(
  has_function_privilege('service_role', 'public.claim_booking_email_outbox(integer,integer)', 'EXECUTE'),
  'A service_role végrehajthatja a szűk claim RPC-t'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz)',
    'EXECUTE'
  ),
  'Az authenticated szerepkör nem rögzíthet worker eredményt'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz)',
    'EXECUTE'
  ),
  'A service_role végrehajthatja a szűk eredményrögzítő RPC-t'
);
select is(
  (select proconfig from pg_proc where oid = 'public.claim_booking_email_outbox(integer,integer)'::regprocedure)
    @> array['search_path=""'],
  true,
  'A claim RPC rögzített üres search_pathot használ'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz)'::regprocedure
  ) @> array['search_path=""'],
  true,
  'Az eredményrögzítő RPC rögzített üres search_pathot használ'
);

insert into auth.users (id, email, raw_user_meta_data) values
  (
    'a4000000-0000-0000-0000-000000000001',
    'email-admin@example.invalid',
    '{"first_name":"Email","last_name":"Admin"}'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'email-user@example.invalid',
    '{"first_name":"Email","last_name":"User"}'
  );

update public.profiles
set role = 'admin'
where id = 'a4000000-0000-0000-0000-000000000001';

insert into public.bookings (
  id,
  room_id,
  user_id,
  created_by,
  start_at,
  end_at,
  use_type,
  status,
  idempotency_key
) values (
  'a4000000-0000-0000-0000-000000000010',
  '11000000-0000-0000-0000-000000000002',
  'a4000000-0000-0000-0000-000000000002',
  'a4000000-0000-0000-0000-000000000001',
  '2030-01-10 09:00 Europe/Budapest',
  '2030-01-10 10:00 Europe/Budapest',
  'individual',
  'active',
  'a4000000-0000-0000-0000-000000000011'
);

select set_config(
  'test.email_outbox_id',
  public.enqueue_booking_email(
    'a4000000-0000-0000-0000-000000000011',
    'booking.created',
    'single',
    'a4000000-0000-0000-0000-000000000010',
    null,
    'a4000000-0000-0000-0000-000000000002',
    'EMAIL-USER@EXAMPLE.INVALID',
    'a4000000-0000-0000-0000-000000000001',
    true,
    1,
    '{"room_name":"1.Szoba-családi","start_at":"2030-01-10T08:00:00Z"}'::jsonb
  )::text,
  true
);

select is(
  public.enqueue_booking_email(
    'a4000000-0000-0000-0000-000000000011',
    'booking.created',
    'single',
    'a4000000-0000-0000-0000-000000000010',
    null,
    'a4000000-0000-0000-0000-000000000002',
    'email-user@example.invalid',
    'a4000000-0000-0000-0000-000000000001',
    true,
    1,
    '{"room_name":"1.Szoba-családi","start_at":"2030-01-10T08:00:00Z"}'::jsonb
  ),
  current_setting('test.email_outbox_id')::uuid,
  'Azonos deduplikációs kulcs és payload ugyanazt az outbox rekordot adja vissza'
);
select is(
  (
    select count(*)
    from public.booking_email_outbox
    where deduplication_key =
      'a4000000-0000-0000-0000-000000000011:booking.created:a4000000-0000-0000-0000-000000000002'
  ),
  1::bigint,
  'Az idempotens enqueue nem duplikál rekordot'
);
select throws_ok(
  $$select public.enqueue_booking_email(
    'a4000000-0000-0000-0000-000000000011',
    'booking.created',
    'single',
    'a4000000-0000-0000-0000-000000000010',
    null,
    'a4000000-0000-0000-0000-000000000002',
    'email-user@example.invalid',
    'a4000000-0000-0000-0000-000000000001',
    true,
    1,
    '{"room_name":"Eltérő szoba"}'::jsonb
  )$$,
  'P0001',
  'Az e-mail deduplikációs kulcs már eltérő értesítéshez tartozik.',
  'Azonos deduplikációs kulcs eltérő payloadhoz nem használható'
);
select throws_ok(
  format(
    'update public.booking_email_outbox set payload = %L::jsonb where id = %L::uuid',
    '{"tampered":true}',
    current_setting('test.email_outbox_id')
  ),
  '42501',
  'booking_email_outbox business data is immutable',
  'Az eseménykori payload nem módosítható'
);
select throws_ok(
  format(
    'delete from public.booking_email_outbox where id = %L::uuid',
    current_setting('test.email_outbox_id')
  ),
  '42501',
  'booking_email_outbox is append-only',
  'Az outbox rekord fizikailag nem törölhető'
);

savepoint rollbacked_enqueue;
select public.enqueue_booking_email(
  'a4000000-0000-0000-0000-000000000030',
  'booking.updated',
  'single',
  'a4000000-0000-0000-0000-000000000010',
  null,
  'a4000000-0000-0000-0000-000000000002',
  'email-user@example.invalid',
  'a4000000-0000-0000-0000-000000000001',
  true,
  1,
  '{"room_name":"Rollback"}'::jsonb
);
rollback to savepoint rollbacked_enqueue;
select is(
  (
    select count(*)
    from public.booking_email_outbox
    where correlation_id = 'a4000000-0000-0000-0000-000000000030'
  ),
  0::bigint,
  'Rollbackelt üzleti tranzakció nem hagy árva e-mail-feladatot'
);

set local role service_role;
select set_config('test.email_claim_count', count(*)::text, true),
       set_config('test.email_lease_token', (array_agg(lease_token))[1]::text, true)
from public.claim_booking_email_outbox(10, 300);
reset role;

select is(current_setting('test.email_claim_count')::integer, 1, 'Az esedékes rekord pontosan egyszer claimelhető');
select is(
  (
    select status || ':' || attempts::text
    from public.booking_email_outbox
    where id = current_setting('test.email_outbox_id')::uuid
  ),
  'sending:0',
  'A claim sending állapotot és még nulla befejezett próbálkozást rögzít'
);

set local role service_role;
select set_config(
  'test.email_second_claim_count',
  (select count(*)::text from public.claim_booking_email_outbox(10, 300)),
  true
);
reset role;
select is(
  current_setting('test.email_second_claim_count')::integer,
  0,
  'Élő lease alatt ugyanaz a rekord nem claimelhető újra'
);

set local role service_role;
select lives_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'retry', null, 'SMTP_TEMPORARY', 'Átmeneti SMTP hiba', 120,
      clock_timestamp() + interval '5 minutes'
    )$$,
    current_setting('test.email_outbox_id'),
    current_setting('test.email_lease_token')
  ),
  'Az átmeneti hiba retry állapotként rögzíthető'
);
reset role;

select is(
  (
    select status || ':' || attempts::text || ':' || last_error_code
    from public.booking_email_outbox
    where id = current_setting('test.email_outbox_id')::uuid
  ),
  'retry:1:SMTP_TEMPORARY',
  'A retry növeli a befejezett próbálkozásszámot és biztonságos hibakódot tárol'
);
select is(
  (
    select count(*)
    from public.booking_email_delivery_attempts
    where outbox_id = current_setting('test.email_outbox_id')::uuid
      and outcome = 'retry'
      and attempt_number = 1
  ),
  1::bigint,
  'A retry külön append-only próbálkozásrekordot hoz létre'
);
select throws_ok(
  format(
    'update public.booking_email_delivery_attempts set error_safe = %L where outbox_id = %L::uuid',
    'átírva',
    current_setting('test.email_outbox_id')
  ),
  '42501',
  'booking_email_delivery_attempts is append-only',
  'A próbálkozásnapló nem módosítható'
);
select throws_ok(
  format(
    'delete from public.booking_email_delivery_attempts where outbox_id = %L::uuid',
    current_setting('test.email_outbox_id')
  ),
  '42501',
  'booking_email_delivery_attempts is append-only',
  'A próbálkozásnapló fizikailag nem törölhető'
);

set local role service_role;
select set_config(
  'test.email_early_retry_count',
  (select count(*)::text from public.claim_booking_email_outbox(10, 300)),
  true
);
reset role;
select is(
  current_setting('test.email_early_retry_count')::integer,
  0,
  'A retry rekord a következő próbálkozási idő előtt nem claimelhető'
);

update public.booking_email_outbox
set next_attempt_at = clock_timestamp() - interval '1 second'
where id = current_setting('test.email_outbox_id')::uuid;

set local role service_role;
select set_config('test.email_retry_claim_count', count(*)::text, true),
       set_config('test.email_retry_lease_token', (array_agg(lease_token))[1]::text, true)
from public.claim_booking_email_outbox(10, 300);
reset role;
select is(
  current_setting('test.email_retry_claim_count')::integer,
  1,
  'Az esedékessé vált retry rekord új lease-szel claimelhető'
);

set local role service_role;
select lives_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'sent', '<booking-test@example.invalid>', null, null, 95, null
    )$$,
    current_setting('test.email_outbox_id'),
    current_setting('test.email_retry_lease_token')
  ),
  'A sikeres SMTP-átadás sent eredményként rögzíthető'
);
reset role;

select is(
  (
    select status || ':' || attempts::text || ':' || provider_message_id || ':' || (sent_at is not null)::text
    from public.booking_email_outbox
    where id = current_setting('test.email_outbox_id')::uuid
  ),
  'sent:2:<booking-test@example.invalid>:true',
  'A sikeres küldés Message-ID-t, időpontot és második próbálkozást rögzít'
);
select throws_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'sent', '<duplicate@example.invalid>', null, null, 1, null
    )$$,
    current_setting('test.email_outbox_id'),
    current_setting('test.email_retry_lease_token')
  ),
  '42501',
  'Az e-mail lease már nem érvényes.',
  'A már lezárt lease eredménye nem játszható vissza'
);

select set_config(
  'test.expired_email_outbox_id',
  public.enqueue_booking_email(
    'a4000000-0000-0000-0000-000000000040',
    'booking.updated',
    'single',
    'a4000000-0000-0000-0000-000000000010',
    null,
    'a4000000-0000-0000-0000-000000000002',
    'email-user@example.invalid',
    'a4000000-0000-0000-0000-000000000002',
    false,
    1,
    '{"room_name":"1.Szoba-családi","change":"time"}'::jsonb
  )::text,
  true
);
select ok(
  current_setting('test.expired_email_outbox_id')::uuid is not null,
  'A lejárt lease tesztre második e-mail-feladat létrejön'
);

set local role service_role;
select set_config('test.expired_old_lease_token', (array_agg(lease_token))[1]::text, true)
from public.claim_booking_email_outbox(1, 30);
reset role;

update public.booking_email_outbox
set leased_at = clock_timestamp() - interval '2 minutes',
    lease_expires_at = clock_timestamp() - interval '1 minute'
where id = current_setting('test.expired_email_outbox_id')::uuid;

set local role service_role;
select set_config('test.expired_new_lease_token', (array_agg(lease_token))[1]::text, true)
from public.claim_booking_email_outbox(1, 30);
reset role;
select isnt(
  current_setting('test.expired_new_lease_token')::uuid,
  current_setting('test.expired_old_lease_token')::uuid,
  'A lejárt lease új tokennel biztonságosan visszavehető'
);

set local role service_role;
select throws_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'captured', null, null, null, 0, null
    )$$,
    current_setting('test.expired_email_outbox_id'),
    current_setting('test.expired_old_lease_token')
  ),
  '42501',
  'Az e-mail lease már nem érvényes.',
  'A visszavétel előtti stale worker nem írhat eredményt'
);
select lives_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'captured', null, null, null, 0, null
    )$$,
    current_setting('test.expired_email_outbox_id'),
    current_setting('test.expired_new_lease_token')
  ),
  'A capture worker a jelenlegi lease-szel lezárhatja a feladatot'
);
reset role;

select is(
  (
    select status || ':' || attempts::text
    from public.booking_email_outbox
    where id = current_setting('test.expired_email_outbox_id')::uuid
  ),
  'captured:1',
  'A staging capture nem jelöl SMTP-küldést, de auditált próbálkozás marad'
);
select is(
  (
    select count(*)
    from public.booking_email_delivery_attempts
    where outbox_id = current_setting('test.expired_email_outbox_id')::uuid
      and outcome = 'captured'
  ),
  1::bigint,
  'A capture eredmény append-only naplóba kerül'
);

select set_config(
  'test.dead_email_outbox_id',
  public.enqueue_booking_email(
    'a4000000-0000-0000-0000-000000000050',
    'booking.cancelled',
    'single',
    'a4000000-0000-0000-0000-000000000010',
    null,
    'a4000000-0000-0000-0000-000000000002',
    'email-user@example.invalid',
    'a4000000-0000-0000-0000-000000000001',
    true,
    1,
    '{"room_name":"1.Szoba-családi","cancelled":true}'::jsonb
  )::text,
  true
);

set local role service_role;
select set_config(
  'test.dead_email_lease_token',
  (select (array_agg(lease_token))[1]::text from public.claim_booking_email_outbox(1, 300)),
  true
);
select lives_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, %L::uuid, 'dead_letter', null, 'SMTP_PERMANENT', 'Tartós címzetthiba', 75, null
    )$$,
    current_setting('test.dead_email_outbox_id'),
    current_setting('test.dead_email_lease_token')
  ),
  'A tartós SMTP-hiba dead-letter eredményként rögzíthető'
);
reset role;

select is(
  (
    select status || ':' || attempts::text || ':' || last_error_code || ':' || (sent_at is null)::text
    from public.booking_email_outbox
    where id = current_setting('test.dead_email_outbox_id')::uuid
  ),
  'dead_letter:1:SMTP_PERMANENT:true',
  'A dead-letter rekord nem jelöl kézbesítést és megőrzi a biztonságos hibakódot'
);

set local role service_role;
select throws_ok(
  $$select * from public.claim_booking_email_outbox(0, 300)$$,
  '22023',
  'A batch mérete 1 és 100 közötti lehet.',
  'A claim RPC korlátozza a batch méretét'
);
select throws_ok(
  format(
    $$select public.complete_booking_email_outbox(
      %L::uuid, extensions.gen_random_uuid(), 'retry', null, null, null, 1,
      clock_timestamp() + interval '1 minute'
    )$$,
    current_setting('test.expired_email_outbox_id')
  ),
  '22023',
  'A kézbesítési eredmény és a hibamezők nem konzisztensek.',
  'Retry hibakód vagy biztonságos hibaüzenet nélkül nem rögzíthető'
);
reset role;

select * from finish();
rollback;
