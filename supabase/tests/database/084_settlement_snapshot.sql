begin;

select plan(24);

select has_function(
  'public',
  'admin_close_monthly_settlement',
  array['uuid','date'],
  'A havi elszámolás lezáró admin RPC létezik'
);
select has_function(
  'public',
  'admin_monthly_settlement_status',
  array['date'],
  'A havi settlement státusz admin RPC létezik'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('84000000-0000-0000-0000-000000000001', 'settlement-admin@example.invalid', '{"first_name":"Settlement","last_name":"Admin"}'),
  ('84000000-0000-0000-0000-000000000002', 'settlement-user@example.invalid', '{"first_name":"Settlement","last_name":"User"}');
update public.profiles set role = 'admin' where id = '84000000-0000-0000-0000-000000000001';

insert into public.user_pricing_policies (
  user_id, pricing_scheme, valid_from, valid_to, created_by
) values (
  '84000000-0000-0000-0000-000000000002',
  'progressive',
  (date_trunc('month', current_date) - interval '1 month')::date,
  null,
  '84000000-0000-0000-0000-000000000001'
);

insert into public.bookings (
  room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key
)
select
  '11000000-0000-0000-0000-000000000002',
  '84000000-0000-0000-0000-000000000002',
  '84000000-0000-0000-0000-000000000002',
  (((date_trunc('month', current_date) - interval '1 month')::date + (g - 1))::text || ' 08:00 Europe/Budapest')::timestamptz,
  (((date_trunc('month', current_date) - interval '1 month')::date + (g - 1))::text || ' 10:00 Europe/Budapest')::timestamptz,
  'individual',
  'active',
  extensions.gen_random_uuid()
from generate_series(1, 10) g;

set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000002', true);
select throws_ok(
  format(
    $$select * from public.admin_close_monthly_settlement(
      '84000000-0000-0000-0000-000000000002', %L::date
    )$$,
    (date_trunc('month', current_date) - interval '1 month')::date
  ),
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem zárhat havi elszámolást'
);
select throws_ok(
  format(
    $$select * from public.admin_monthly_settlement_status(%L::date)$$,
    (date_trunc('month', current_date) - interval '1 month')::date
  ),
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem olvashat admin settlement státuszt'
);

select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000001', true);
select throws_ok(
  format(
    $$select * from public.admin_close_monthly_settlement(
      '84000000-0000-0000-0000-000000000002', %L::date
    )$$,
    date_trunc('month', current_date)::date
  ),
  '22023',
  'Csak már befejeződött hónap zárható le.',
  'Aktuális hónap nem zárható le idő előtt'
);

select lives_ok(
  format(
    $$select * from public.admin_close_monthly_settlement(
      '84000000-0000-0000-0000-000000000002', %L::date
    )$$,
    (date_trunc('month', current_date) - interval '1 month')::date
  ),
  'Admin lezárhatja az előző hónap progresszív elszámolását'
);
reset role;

select is(
  (
    select sr.calculated_due_huf
    from public.monthly_settlements ms
    join public.settlement_revisions sr on sr.id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  50000::bigint,
  'A lezárt 20 órás progresszív összeg 50 000 Ft'
);

select is(
  (
    select ms.is_closed
    from public.monthly_settlements ms
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  true,
  'A havi settlement lezárt állapotba kerül'
);

select is(
  (
    select sr.pricing_scheme
    from public.monthly_settlements ms
    join public.settlement_revisions sr on sr.id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  'progressive'::public.user_pricing_scheme,
  'A revision megőrzi a progresszív díjazási módot'
);

select is(
  (
    select sum(sbl.amount_huf)::bigint
    from public.monthly_settlements ms
    join public.settlement_booking_lines sbl on sbl.settlement_revision_id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  50000::bigint,
  'A snapshot sorok összege megegyezik a központi számítással'
);

select is(
  (
    select sum(sbl.duration_minutes)::integer
    from public.monthly_settlements ms
    join public.settlement_booking_lines sbl on sbl.settlement_revision_id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  1200,
  'A snapshot pontosan 20 óra időtartamot őriz'
);

select is(
  (
    select count(*)
    from (
      select sbl.booking_id
      from public.monthly_settlements ms
      join public.settlement_booking_lines sbl on sbl.settlement_revision_id = ms.closed_revision_id
      where ms.user_id = '84000000-0000-0000-0000-000000000002'
        and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
      group by sbl.booking_id
      having count(*) > 1
    ) split_bookings
  ),
  1::bigint,
  'A 15 órás progresszív határt átlépő egyetlen foglalás két díjrészre bomlik'
);

select ok(
  (
    select bool_and(sbl.pricing_scheme = 'progressive'::public.user_pricing_scheme)
    from public.monthly_settlements ms
    join public.settlement_booking_lines sbl on sbl.settlement_revision_id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  'Minden snapshot sorrész megőrzi a progresszív díjazási módot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '84000000-0000-0000-0000-000000000001', true);
select is(
  (
    select calculated_due_huf
    from public.admin_monthly_settlement_status((date_trunc('month', current_date) - interval '1 month')::date)
    where user_id = '84000000-0000-0000-0000-000000000002'
  ),
  50000::bigint,
  'Az admin státusz read model a lezárt snapshot összegét adja vissza'
);
select throws_ok(
  format(
    $$select * from public.admin_close_monthly_settlement(
      '84000000-0000-0000-0000-000000000002', %L::date
    )$$,
    (date_trunc('month', current_date) - interval '1 month')::date
  ),
  'P0001',
  'Ez a havi elszámolás már le van zárva.',
  'Ugyanaz a hónap nem zárható le másodszor'
);
reset role;

select throws_ok(
  $$update public.settlement_revisions
    set calculated_due_huf = 1
    where id = (
      select closed_revision_id
      from public.monthly_settlements
      where user_id = '84000000-0000-0000-0000-000000000002'
        and settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
    )$$,
  '42501',
  'A lezárt elszámolási snapshot nem módosítható.',
  'A lezárt revision immutable'
);

select throws_ok(
  $$update public.settlement_booking_lines
    set amount_huf = amount_huf + 1
    where settlement_revision_id = (
      select closed_revision_id
      from public.monthly_settlements
      where user_id = '84000000-0000-0000-0000-000000000002'
        and settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
    )$$,
  '42501',
  'A lezárt elszámolási snapshot nem módosítható.',
  'A lezárt booking snapshot sorok UPDATE ellen immutable-ek'
);

select throws_ok(
  $$delete from public.settlement_booking_lines
    where settlement_revision_id = (
      select closed_revision_id
      from public.monthly_settlements
      where user_id = '84000000-0000-0000-0000-000000000002'
        and settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
    )$$,
  '42501',
  'A lezárt elszámolási snapshot nem módosítható.',
  'A lezárt booking snapshot sorok DELETE ellen is immutable-ek'
);

select throws_ok(
  $$insert into public.settlement_booking_lines (
      settlement_revision_id, booking_id, duration_minutes, pricing_mode,
      pricing_rule_id, hourly_rate_huf, amount_huf, line_part_index,
      pricing_scheme, line_kind
    )
    select
      sbl.settlement_revision_id, sbl.booking_id, sbl.duration_minutes,
      sbl.pricing_mode, sbl.pricing_rule_id, sbl.hourly_rate_huf,
      sbl.amount_huf, sbl.line_part_index + 100,
      sbl.pricing_scheme, sbl.line_kind
    from public.settlement_booking_lines sbl
    where sbl.settlement_revision_id = (
      select closed_revision_id
      from public.monthly_settlements
      where user_id = '84000000-0000-0000-0000-000000000002'
        and settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
    )
    order by sbl.id
    limit 1$$,
  '42501',
  'Lezárt elszámolási snapshothoz nem adható új booking sor.',
  'Lezárt snapshothoz privilegizált sessionből sem fűzhető új booking sor'
);

select is(
  (
    select count(*)
    from public.monthly_settlements ms
    join public.settlement_booking_lines sbl
      on sbl.settlement_revision_id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  11::bigint,
  'A sikertelen utólagos INSERT után a lezárt snapshot sorszáma változatlan'
);

select throws_ok(
  $$insert into public.settlement_revisions (
      settlement_id, revision_number, normal_minutes, special_minutes,
      calculated_due_huf, calculation_input_hash, calculated_by,
      pricing_scheme, pricing_breakdown
    )
    select
      ms.id, 999, sr.normal_minutes, sr.special_minutes,
      sr.calculated_due_huf, sr.calculation_input_hash, sr.calculated_by,
      sr.pricing_scheme, sr.pricing_breakdown
    from public.monthly_settlements ms
    join public.settlement_revisions sr on sr.id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date$$,
  '42501',
  'Lezárt havi elszámoláshoz nem adható új revision.',
  'Lezárt settlementhez privilegizált sessionből sem fűzhető új revision'
);

select throws_ok(
  $$update public.monthly_settlements
    set is_closed = false,
        closed_at = null,
        closed_by = null,
        closed_revision_id = null
    where user_id = '84000000-0000-0000-0000-000000000002'
      and settlement_month = (date_trunc('month', current_date) - interval '1 month')::date$$,
  '42501',
  'A lezárt havi elszámolás lezárási adatai nem módosíthatók.',
  'A lezárt revision-kapcsolat privilegizált sessionből sem nullázható'
);

select is(
  (
    select count(*)
    from public.audit_logs al
    where al.action = 'monthly_settlement.closed'
      and al.after_data ->> 'user_id' = '84000000-0000-0000-0000-000000000002'
  ),
  1::bigint,
  'A havi lezárás auditnaplóba kerül'
);

select ok(
  (
    select jsonb_array_length(sr.pricing_breakdown) > 0
    from public.monthly_settlements ms
    join public.settlement_revisions sr on sr.id = ms.closed_revision_id
    where ms.user_id = '84000000-0000-0000-0000-000000000002'
      and ms.settlement_month = (date_trunc('month', current_date) - interval '1 month')::date
  ),
  'A revision a teljes díjszámítási breakdown snapshotot is megőrzi'
);

select * from finish();
rollback;
