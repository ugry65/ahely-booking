begin;

select plan(29);

select has_function(
  'public',
  'enqueue_booking_email_from_audit',
  array[]::text[],
  'A deferred booking audit -> e-mail bridge létezik'
);
select has_trigger(
  'public',
  'audit_logs',
  'booking_email_from_audit',
  'A booking audit e-mail constraint trigger létezik'
);
select ok(
  (
    select trigger.tgdeferrable and trigger.tginitdeferred
    from pg_trigger trigger
    where trigger.tgrelid = 'public.audit_logs'::regclass
      and trigger.tgname = 'booking_email_from_audit'
  ),
  'Az enqueue trigger tranzakció végéig halasztott'
);
select ok(
  not has_function_privilege('authenticated', 'public.enqueue_booking_email_from_audit()', 'EXECUTE'),
  'Az authenticated szerepkör nem hívhatja közvetlenül az audit bridge-et'
);
select is(
  (
    select proconfig
    from pg_proc
    where oid = 'public.enqueue_booking_email_from_audit()'::regprocedure
  ) @> array['search_path=""'],
  true,
  'Az audit bridge rögzített üres search_pathot használ'
);

insert into auth.users (id, email, raw_user_meta_data) values
  (
    'a5000000-0000-0000-0000-000000000001',
    'enqueue-admin@example.invalid',
    '{"first_name":"Enqueue","last_name":"Admin"}'
  ),
  (
    'a5000000-0000-0000-0000-000000000002',
    'enqueue-owner@example.invalid',
    '{"first_name":"Enqueue","last_name":"Owner"}'
  );

update public.profiles
set role = 'admin'
where id = 'a5000000-0000-0000-0000-000000000001';

select set_config('request.jwt.claim.sub', 'a5000000-0000-0000-0000-000000000001', true);

select set_config(
  'test.email_single_booking_id',
  public.create_booking(
    '11000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000002',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '10:00') at time zone 'Europe/Budapest',
    'individual',
    'E-mailben nem szerepelhet',
    'a5000000-0000-0000-0000-000000000101',
    'Első konzultáció'
  )::text,
  true
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000101'),
  1::bigint,
  'Egyedi create pontosan egy e-mail feladatot készít'
);
select results_eq(
  $$
    select event_type, scope, recipient_user_id, actor_user_id, performed_by_admin
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  $$,
  $$values (
    'booking.created'::text,
    'single'::text,
    'a5000000-0000-0000-0000-000000000002'::uuid,
    'a5000000-0000-0000-0000-000000000001'::uuid,
    true
  )$$,
  'Admin create címzettje a booking owner, adminjelzéssel'
);
select is(
  (
    select payload ->> 'booking_title'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  ),
  'Első konzultáció',
  'A create payload a wrapper után beállított címet őrzi'
);
select ok(
  not (
    select payload ? 'note'
      or payload::text like '%E-mailben nem szerepelhet%'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  ),
  'A foglalási megjegyzés nem kerül az e-mail payloadba'
);

select is(
  public.create_booking(
    '11000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000002',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 40) + time '10:00') at time zone 'Europe/Budapest',
    'individual',
    'E-mailben nem szerepelhet',
    'a5000000-0000-0000-0000-000000000101',
    'Első konzultáció'
  ),
  current_setting('test.email_single_booking_id')::uuid,
  'Az idempotens create retry ugyanazt a bookingot adja vissza'
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;
select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000101'),
  1::bigint,
  'Az idempotens create retry nem duplikál e-mail feladatot'
);

select is(
  public.update_booking(
    current_setting('test.email_single_booking_id')::uuid,
    (select updated_at from public.bookings where id = current_setting('test.email_single_booking_id')::uuid),
    '11000000-0000-0000-0000-000000000003',
    (select start_at + interval '1 hour' from public.bookings where id = current_setting('test.email_single_booking_id')::uuid),
    (select end_at + interval '1 hour' from public.bookings where id = current_setting('test.email_single_booking_id')::uuid),
    'group',
    'Új titkos megjegyzés',
    'a5000000-0000-0000-0000-000000000102',
    'Csoportos konzultáció'
  ),
  current_setting('test.email_single_booking_id')::uuid,
  'Az egyedi booking admin által módosítható'
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000102'),
  1::bigint,
  'Egyedi update pontosan egy e-mail feladatot készít'
);
select results_eq(
  $$
    select payload #>> '{before,room_name}', payload #>> '{after,room_name}',
           payload #>> '{before,booking_title}', payload #>> '{after,booking_title}'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000102'
  $$,
  $$values ('1.Szoba-családi'::text, '2.Szoba'::text, 'Első konzultáció'::text, 'Csoportos konzultáció'::text)$$,
  'Az update payload a releváns előző és új adatokat őrzi'
);
select ok(
  not (
    select payload::text like '%Új titkos megjegyzés%'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000102'
  ),
  'Az update payload sem tartalmaz foglalási megjegyzést'
);

select is(
  public.cancel_booking(
    current_setting('test.email_single_booking_id')::uuid,
    'Ügyfél kérésére',
    'a5000000-0000-0000-0000-000000000103'
  ),
  current_setting('test.email_single_booking_id')::uuid,
  'Az admin lemondhatja az egyedi bookingot'
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000103'),
  1::bigint,
  'Egyedi cancel pontosan egy e-mail feladatot készít'
);
select results_eq(
  $$
    select event_type, recipient_user_id, payload ->> 'cancellation_reason', payload ->> 'booking_title'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000103'
  $$,
  $$values (
    'booking.cancelled'::text,
    'a5000000-0000-0000-0000-000000000002'::uuid,
    'Ügyfél kérésére'::text,
    'Csoportos konzultáció'::text
  )$$,
  'A cancel snapshot megőrzi az okot, címet és tulajdonost'
);

select set_config(
  'test.email_series_id',
  public.create_booking_series(
    '11000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000002',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 50) + time '09:00') at time zone 'Europe/Budapest',
    (((clock_timestamp() at time zone 'Europe/Budapest')::date + 50) + time '10:00') at time zone 'Europe/Budapest',
    'daily', null, 3, '{}'::date[], 'abort_all', 'individual', 'Sorozat titkos jegyzet',
    'a5000000-0000-0000-0000-000000000104', 'Három alkalom'
  ) ->> 'series_id',
  true
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000104'),
  1::bigint,
  'Sorozat create egyetlen összefoglaló e-mail feladatot készít'
);
select results_eq(
  $$
    select scope, series_id, booking_id, (payload ->> 'affected_count')::integer,
           payload ->> 'booking_title'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000104'
  $$,
  $$values (
    'series'::text,
    current_setting('test.email_series_id')::uuid,
    null::uuid,
    3,
    'Három alkalom'::text
  )$$,
  'A sorozat create payloadja helyes scope-ot, darabszámot és címet őriz'
);

select set_config(
  'test.email_series_first_booking_id',
  (
    select id::text
    from public.bookings
    where series_id = current_setting('test.email_series_id')::uuid
    order by start_at
    limit 1
  ),
  true
);
select is(
  public.update_booking_scope(
    current_setting('test.email_series_first_booking_id')::uuid,
    'occurrence',
    (select updated_at from public.bookings where id = current_setting('test.email_series_first_booking_id')::uuid),
    '11000000-0000-0000-0000-000000000003',
    (select start_at + interval '1 hour' from public.bookings where id = current_setting('test.email_series_first_booking_id')::uuid),
    (select end_at + interval '1 hour' from public.bookings where id = current_setting('test.email_series_first_booking_id')::uuid),
    'individual', 'Occurrence titkos jegyzet',
    'a5000000-0000-0000-0000-000000000105', 'Első alkalom módosítva'
  ),
  1,
  'Az occurrence scope update egy alkalmat módosít'
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select results_eq(
  $$
    select
      (select count(*) from public.booking_email_outbox
       where correlation_id = 'a5000000-0000-0000-0000-000000000105'),
      scope, booking_id, series_id, (payload ->> 'affected_count')::integer
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000105'
  $$,
  $$values (
    1::bigint,
    'occurrence'::text,
    current_setting('test.email_series_first_booking_id')::uuid,
    current_setting('test.email_series_id')::uuid,
    1
  )$$,
  'Occurrence update egyetlen, mindkét forrásazonosítót tartalmazó e-mailt készít'
);

select set_config(
  'test.email_series_second_booking_id',
  (
    select id::text
    from public.bookings
    where series_id = current_setting('test.email_series_id')::uuid
      and status = 'active'
    order by start_at
    offset 1 limit 1
  ),
  true
);
select is(
  public.cancel_booking_scope(
    current_setting('test.email_series_second_booking_id')::uuid,
    'following',
    'A hátralévő alkalmak elmaradnak',
    'a5000000-0000-0000-0000-000000000106'
  ),
  2,
  'A following cancel két alkalmat mond le'
);
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select results_eq(
  $$
    select
      (select count(*) from public.booking_email_outbox
       where correlation_id = 'a5000000-0000-0000-0000-000000000106'),
      scope, series_id, booking_id, (payload ->> 'affected_count')::integer,
      payload ->> 'cancellation_reason'
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000106'
  $$,
  $$values (
    1::bigint,
    'following'::text,
    current_setting('test.email_series_id')::uuid,
    null::uuid,
    2,
    'A hátralévő alkalmak elmaradnak'::text
  )$$,
  'Following cancel pontosan egy összefoglaló e-mailt készít'
);

select set_config(
  'test.email_create_payload',
  (
    select payload::text
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  ),
  true
);
update public.profiles
set first_name = 'Későbbi', last_name = 'Névváltozás', email = 'changed-owner@example.invalid'
where id = 'a5000000-0000-0000-0000-000000000002';
update public.bookings
set booking_title = 'Későbbi cím'
where id = current_setting('test.email_single_booking_id')::uuid;

select is(
  (
    select payload::text
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  ),
  current_setting('test.email_create_payload'),
  'A payload későbbi profil- és bookingmódosítás után változatlan'
);
select is(
  (
    select recipient_email
    from public.booking_email_outbox
    where correlation_id = 'a5000000-0000-0000-0000-000000000101'
  ),
  'enqueue-owner@example.invalid',
  'A címzett eseménykori e-mail címe változatlan marad'
);

do $rollback_test$
begin
  begin
    perform public.create_booking(
      '11000000-0000-0000-0000-000000000004',
      'a5000000-0000-0000-0000-000000000002',
      (((clock_timestamp() at time zone 'Europe/Budapest')::date + 60) + time '09:00') at time zone 'Europe/Budapest',
      (((clock_timestamp() at time zone 'Europe/Budapest')::date + 60) + time '10:00') at time zone 'Europe/Budapest',
      'individual', null, 'a5000000-0000-0000-0000-000000000107', 'Rollback próba'
    );
    raise exception 'szándékos rollback';
  exception when others then
    if sqlerrm <> 'szándékos rollback' then
      raise;
    end if;
  end;
end;
$rollback_test$;
set constraints booking_email_from_audit immediate;
set constraints booking_email_from_audit deferred;

select is(
  (select count(*) from public.bookings where idempotency_key = 'a5000000-0000-0000-0000-000000000107'),
  0::bigint,
  'A visszagörgetett create nem hagy bookingot'
);
select is(
  (select count(*) from public.booking_email_outbox where correlation_id = 'a5000000-0000-0000-0000-000000000107'),
  0::bigint,
  'A visszagörgetett create nem hagy e-mail feladatot'
);

select is(
  (
    select count(*)
    from public.booking_email_outbox
    where recipient_user_id = 'a5000000-0000-0000-0000-000000000002'
  ),
  6::bigint,
  'A teljes sikeres műveletsor hat logikai művelethez hat e-mail feladatot készít'
);

select * from finish();
rollback;
