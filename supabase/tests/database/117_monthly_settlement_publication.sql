begin;

select plan(28);

select has_table('public', 'monthly_settlement_periods', 'A havi publikálási esemény önálló, változtathatatlan rekord');
select has_function('public', 'admin_monthly_settlement_close_preview', array['date'], 'Az admin lezárás előnézete elérhető');
select has_function('public', 'admin_close_monthly_settlement_period', array['date'], 'Az admin havi lezárás tranzakció elérhető');
select has_function('public', 'list_my_latest_closed_monthly_settlement', array[]::text[], 'A saját lezárt elszámolás user ID paraméter nélkül olvasható');
select ok(not has_table_privilege('authenticated', 'public.monthly_settlements', 'SELECT'), 'A kliens nem olvashat közvetlenül havi pénzügyi táblát');
select ok(not has_table_privilege('authenticated', 'public.settlement_revisions', 'SELECT'), 'A kliens nem olvashat közvetlenül revision táblát');

insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000271'::uuid, 'settlement-admin@example.invalid', '{"first_name":"Settlement","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000272'::uuid, 'settlement-user-a@example.invalid', '{"first_name":"Settlement","last_name":"A"}'),
  ('00000000-0000-0000-0000-000000000273'::uuid, 'settlement-user-b@example.invalid', '{"first_name":"Settlement","last_name":"B"}'),
  ('00000000-0000-0000-0000-000000000274', 'settlement-user-empty@example.invalid', '{"first_name":"Settlement","last_name":"Empty"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000271'::uuid;

insert into public.bookings(id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key)
select '41000000-0000-0000-0000-000000000271'::uuid, '11000000-0000-0000-0000-000000000002'::uuid,
  '00000000-0000-0000-0000-000000000272'::uuid, '00000000-0000-0000-0000-000000000271'::uuid,
  timezone('Europe/Budapest', date_trunc('month', timezone('Europe/Budapest', now()))::date + 1 + time '07:00'),
  timezone('Europe/Budapest', date_trunc('month', timezone('Europe/Budapest', now()))::date + 1 + time '08:00'),
  'individual', 'active', gen_random_uuid()
union all
select '41000000-0000-0000-0000-000000000272'::uuid, '11000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000273'::uuid, '00000000-0000-0000-0000-000000000271'::uuid,
  timezone('Europe/Budapest', date_trunc('month', timezone('Europe/Budapest', now()))::date + 1 + time '07:00'),
  timezone('Europe/Budapest', date_trunc('month', timezone('Europe/Budapest', now()))::date + 1 + time '08:00'),
  'individual', 'active', gen_random_uuid();

select is(
  public.monthly_settlement_cutoff_blockers(
    date_trunc('month', timezone('Europe/Budapest', now()))::date,
    (select start_at - interval '24 hours' from public.bookings where id = '41000000-0000-0000-0000-000000000271'::uuid)
  ),
  1::bigint,
  'Foglalás a pontos 24 órás határnál még blokkolja a lezárást'
);
select is(
  public.monthly_settlement_cutoff_blockers(
    date_trunc('month', timezone('Europe/Budapest', now()))::date,
    timezone('Europe/Budapest', ((date_trunc('month', timezone('Europe/Budapest', now())) + interval '1 month')::date - 1) + time '23:45')
  ),
  0::bigint,
  'A hónap utolsó napjának végére minden korábbi foglalás lezárhatóvá válik'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000272'::uuid, true);
select is((select count(*) from public.list_my_latest_closed_monthly_settlement()), 0::bigint, 'Lezárás előtt a user nem kap végleges pénzügyi összeget');
select throws_ok(
  $$select * from public.admin_close_monthly_settlement_period(date_trunc('month', timezone('Europe/Budapest', now()))::date)$$,
  '42501', null, 'Normál user nem zárhat le hónapot'
);
select throws_ok(
  $$select * from public.monthly_settlements$$,
  '42501', null, 'Normál user nem tud közvetlen táblalekérdezéssel más elszámolást olvasni'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000271'::uuid, true);
select is(
  (select can_close from public.admin_monthly_settlement_close_preview(date_trunc('month', timezone('Europe/Budapest', now()))::date)),
  true,
  'Az aktuális hónap lezárható, ha nincs még módosítható foglalás'
);
select lives_ok(
  $$select * from public.admin_close_monthly_settlement_period(date_trunc('month', timezone('Europe/Budapest', now()))::date)$$,
  'Admin lezárhatja az aktuális hónapot, nem kell megvárnia a következő hónapot'
);
select throws_ok(
  $$select * from public.admin_close_monthly_settlement_period(date_trunc('month', timezone('Europe/Budapest', now()))::date)$$,
  'P0001', 'Ez a hónap már le van zárva.', 'Az ismételt zárás nem hoz létre új pénzügyi állapotot'
);
select throws_ok(
  $$select * from public.admin_close_monthly_settlement_period((date_trunc('month', timezone('Europe/Budapest', now())) + interval '1 month')::date)$$,
  '22023', 'Jövőbeli hónap nem zárható le.', 'Nem jogosult hónap lezárása hibával áll le'
);
reset role;
select is(
  (select count(*) from public.monthly_settlement_periods where settlement_month = date_trunc('month', timezone('Europe/Budapest', now()))::date),
  1::bigint,
  'Ismételt lezárási kísérlet után csak egy hónapzárási pénzügyi állapot marad'
);

select set_config('test.published_user_a_due', (
  select revision.calculated_due_huf::text
  from public.monthly_settlements settlement
  join public.settlement_revisions revision on revision.id = settlement.closed_revision_id
  where settlement.user_id = '00000000-0000-0000-0000-000000000272'::uuid
), true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000272'::uuid, true);
select is(
  (select count(*) from public.list_my_latest_closed_monthly_settlement()),
  1::bigint,
  'Publikálás után user A kizárólag a saját elszámolását kapja'
);
select is(
  (select calculated_due_huf from public.list_my_latest_closed_monthly_settlement()),
  current_setting('test.published_user_a_due')::bigint,
  'A usernek megjelenített összeg a lezárt revision összegével egyezik'
);
reset role;
set local role service_role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000272'::uuid, true);
select throws_ok(
  $$update public.bookings set status = 'cancelled' where id = '41000000-0000-0000-0000-000000000271'::uuid$$,
  '42501', null, 'Lezárt hónap foglalását még privilegizált API szerepkör sem írhatja normál userként'
);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000272'::uuid, true);
select is(
  (select count(*) from public.list_my_latest_closed_monthly_settlement()),
  1::bigint,
  'A saját adat RPC nem fogad másik user azonosítót, így más elszámolása nem kérhető le'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000274', true);
select is((select count(*) from public.list_my_latest_closed_monthly_settlement()), 0::bigint, 'Másik user pénzügyi adata nem szivárog át');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000271'::uuid, true);
select lives_ok(
  $$select * from public.admin_correct_historical_booking_rate('41000000-0000-0000-0000-000000000271'::uuid,4100,'Tesztelt admin korrekció',gen_random_uuid())$$,
  'Admin indoklással új korrekciós revisiont hozhat létre'
);
reset role;
select is(
  (select count(*) from public.settlement_revisions revision join public.monthly_settlements settlement on settlement.id = revision.settlement_id where settlement.user_id = '00000000-0000-0000-0000-000000000272'::uuid),
  2::bigint,
  'A régi revision megmarad, az új revision külön rekord'
);
select ok(
  (select revision.calculated_due_huf = 4100 and revision.revision_number = 2
   from public.monthly_settlements settlement join public.settlement_revisions revision on revision.id = settlement.closed_revision_id
   where settlement.user_id = '00000000-0000-0000-0000-000000000272'::uuid),
  'Korrekció után az új revision lesz aktív és az új összeg jelenik meg'
);
select is(
  (select revision.calculated_due_huf from public.monthly_settlements settlement
   join public.settlement_revisions revision on revision.settlement_id = settlement.id
   where settlement.user_id = '00000000-0000-0000-0000-000000000272'::uuid and revision.revision_number = 1),
  current_setting('test.published_user_a_due')::bigint,
  'Korrekció után is auditálható az eredeti lezárt revision összege'
);
select is(
  (select count(*) from public.audit_logs where action = 'monthly_settlement.corrected' and reason = 'Tesztelt admin korrekció'),
  1::bigint,
  'A korrekció indoklása és új revisionje auditálható'
);
select set_config('ahely.internal_settlement_correction', 'off', true);
select lives_ok(
  $$select public.cancel_booking_scope('41000000-0000-0000-0000-000000000271'::uuid,'occurrence','Admin utólagos törlés indoka',gen_random_uuid())$$,
  'Admin a lezárás után is lemondhat foglalást, auditindokkal új revision készül'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000272'::uuid, true);
select is(
  (select calculated_due_huf from public.list_my_latest_closed_monthly_settlement()),
  0::bigint,
  'Admin lemondása után user az új érvényes revision összegét látja'
);
reset role;

select * from finish();
rollback;
