begin;

select plan(12);

insert into auth.users (id, email, raw_user_meta_data) values
  ('85000000-0000-0000-0000-000000000001', 'group-rate-admin@example.invalid', '{"first_name":"GroupRate","last_name":"Admin"}'),
  ('85000000-0000-0000-0000-000000000002', 'group-rate-user@example.invalid', '{"first_name":"GroupRate","last_name":"User"}');
update public.profiles set role = 'admin' where id = '85000000-0000-0000-0000-000000000001';

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'bookings' and column_name = 'group_hourly_rate_huf'
  ),
  'A foglalás tárolja a Tréningterem csoportos óradíját'
);

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key
) values
  ('85000000-0000-0000-0000-000000000101', '11000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '2026-08-24 08:00 Europe/Budapest', '2026-08-24 09:00 Europe/Budapest', 'group', 'active', gen_random_uuid()),
  ('85000000-0000-0000-0000-000000000102', '11000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '2026-08-24 09:00 Europe/Budapest', '2026-08-24 10:00 Europe/Budapest', 'group', 'active', gen_random_uuid()),
  ('85000000-0000-0000-0000-000000000103', '11000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '2026-08-24 10:00 Europe/Budapest', '2026-08-24 11:00 Europe/Budapest', 'individual', 'active', gen_random_uuid());

select is(
  (select group_hourly_rate_huf from public.bookings where id = '85000000-0000-0000-0000-000000000101'),
  5000::bigint,
  'Tréningterem csoportos foglalás default díja 5 000 Ft/óra'
);
select is(
  (select group_hourly_rate_huf from public.bookings where id = '85000000-0000-0000-0000-000000000103'),
  null::bigint,
  'Normál/egyéni foglalás nem kap csoportos óradíjat'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.admin_set_booking_group_rate('85000000-0000-0000-0000-000000000102', 7500, gen_random_uuid())$$,
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem írhatja felül a csoportos díjat'
);

select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select public.admin_set_booking_group_rate('85000000-0000-0000-0000-000000000102', 7500, '85000000-0000-0000-0000-000000000201')$$,
  'Admin foglalásonként felülírhatja a csoportos díjat'
);
reset role;

select is(
  (select group_hourly_rate_huf from public.bookings where id = '85000000-0000-0000-0000-000000000102'),
  7500::bigint,
  'Az egyedi 7 500 Ft/óra díj a foglaláson rögzül'
);
select is(
  (select count(*) from public.audit_logs where action = 'booking.group_rate_changed' and entity_id = '85000000-0000-0000-0000-000000000102'),
  1::bigint,
  'Az admin díjfelülírás auditált'
);
select is(
  (select special_due_huf from public.calculate_monthly_pricing('85000000-0000-0000-0000-000000000002', '2026-08-01')),
  12500::bigint,
  'A havi számítás foglalásonként használja az 5 000 + 7 500 Ft-os díjat'
);

insert into public.user_pricing_policies(user_id, pricing_scheme, valid_from, created_by)
values ('85000000-0000-0000-0000-000000000002', 'free', '2026-08-01', '85000000-0000-0000-0000-000000000001');
select is(
  (select calculated_due_huf from public.calculate_monthly_pricing('85000000-0000-0000-0000-000000000002', '2026-08-01')),
  0::bigint,
  'Free díjazás a foglaláson tárolt csoportos díjat is nullázza'
);

-- Lezárt havi snapshot: ugyanaz a két külön foglalási díj maradjon történetileg megőrizve.
insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key
) values
  ('85000000-0000-0000-0000-000000000111', '11000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '2026-07-10 08:00 Europe/Budapest', '2026-07-10 09:00 Europe/Budapest', 'group', 'active', gen_random_uuid()),
  ('85000000-0000-0000-0000-000000000112', '11000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000002', '85000000-0000-0000-0000-000000000001', '2026-07-10 09:00 Europe/Budapest', '2026-07-10 10:00 Europe/Budapest', 'group', 'active', gen_random_uuid());
update public.bookings set group_hourly_rate_huf = 7500 where id = '85000000-0000-0000-0000-000000000112';

set local role authenticated;
select set_config('request.jwt.claim.sub', '85000000-0000-0000-0000-000000000001', true);
select lives_ok(
  $$select * from public.admin_close_monthly_settlement('85000000-0000-0000-0000-000000000002', '2026-07-01')$$,
  'A múlt havi settlement lezárható eltérő foglalási csoportdíjakkal'
);
reset role;

select is(
  (
    select sum(sbl.amount_huf)::bigint
    from public.settlement_booking_lines sbl
    join public.settlement_revisions sr on sr.id = sbl.settlement_revision_id
    join public.monthly_settlements ms on ms.id = sr.settlement_id
    where ms.user_id = '85000000-0000-0000-0000-000000000002'
      and ms.settlement_month = '2026-07-01'
      and sbl.line_kind = 'special_room'
  ),
  12500::bigint,
  'A snapshot összege a foglalásonkénti 5 000 + 7 500 Ft díjat őrzi'
);
select is(
  (
    select string_agg(distinct sbl.hourly_rate_huf::text, ',' order by sbl.hourly_rate_huf::text)
    from public.settlement_booking_lines sbl
    join public.settlement_revisions sr on sr.id = sbl.settlement_revision_id
    join public.monthly_settlements ms on ms.id = sr.settlement_id
    where ms.user_id = '85000000-0000-0000-0000-000000000002'
      and ms.settlement_month = '2026-07-01'
      and sbl.line_kind = 'special_room'
  ),
  '5000,7500',
  'A snapshot külön megőrzi mindkét alkalmazott csoportos óradíjat'
);

select * from finish();
rollback;
