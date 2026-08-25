begin;

select plan(17);

select has_function('public', 'admin_set_user_pricing_policy', array['uuid','user_pricing_scheme','date','uuid'], 'A user díjazási mód admin RPC létezik');
select has_function('public', 'admin_list_user_pricing_policies', array[]::text[], 'A user díjazási mód lista RPC létezik');
select ok(
  not has_function_privilege('authenticated', 'public.effective_user_pricing_scheme(uuid,date)', 'EXECUTE'),
  'A belső effektív díjazási függvény közvetlenül nem hívható'
);
select ok(
  (
    select bool_and(prosecdef and coalesce(proconfig @> array['search_path=""'], false))
    from pg_proc
    where oid in (
      'public.admin_set_user_pricing_policy(uuid,public.user_pricing_scheme,date,uuid)'::regprocedure,
      'public.admin_list_user_pricing_policies()'::regprocedure,
      'public.effective_user_pricing_scheme(uuid,date)'::regprocedure
    )
  ),
  'A díjazási RPC-k SECURITY DEFINER és üres search_path beállításúak'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000821', 'pricing-admin@example.invalid', '{"first_name":"Pricing","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000822', 'pricing-user@example.invalid', '{"first_name":"Pricing","last_name":"User"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000000821';

select is(
  public.effective_user_pricing_scheme('00000000-0000-0000-0000-000000000822', date_trunc('month', current_date)::date),
  'tiered'::public.user_pricing_scheme,
  'Explicit beállítás nélkül a default díjazás sávos'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000822', true);
select throws_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'progressive', %L::date, gen_random_uuid())$$,
    date_trunc('month', current_date)::date
  ),
  '42501',
  'Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.',
  'Normál user nem állíthat díjazási módot'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000821', true);
select throws_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'progressive', %L::date, gen_random_uuid())$$,
    (date_trunc('month', current_date)::date + 1)
  ),
  '22023',
  'A díjazási mód érvényessége csak hónap első napján kezdődhet.',
  'Hónap közepi díjazási mód nem hozható létre'
);
select throws_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'progressive', %L::date, gen_random_uuid())$$,
    (date_trunc('month', current_date)::date - interval '1 month')::date
  ),
  '22023',
  'Korábbi lezárt hónap díjazási módja nem módosítható.',
  'Korábbi hónapra nem lehet visszadátumozni'
);

select lives_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'progressive', %L::date,
      '82000000-0000-0000-0000-000000000001')$$,
    date_trunc('month', current_date)::date
  ),
  'Admin progresszív módot állíthat be az aktuális hónaptól'
);
select lives_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'free', %L::date,
      '82000000-0000-0000-0000-000000000002')$$,
    (date_trunc('month', current_date) + interval '1 month')::date
  ),
  'Admin jövőbeli Free módot állíthat be'
);
reset role;

select is(
  public.effective_user_pricing_scheme('00000000-0000-0000-0000-000000000822', date_trunc('month', current_date)::date),
  'progressive'::public.user_pricing_scheme,
  'Az aktuális hónap progresszív'
);
select is(
  public.effective_user_pricing_scheme('00000000-0000-0000-0000-000000000822', (date_trunc('month', current_date) + interval '1 month')::date),
  'free'::public.user_pricing_scheme,
  'A következő hónap Free'
);
select is(
  (
    select valid_to
    from public.user_pricing_policies
    where user_id = '00000000-0000-0000-0000-000000000822'
      and pricing_scheme = 'progressive'
  ),
  ((date_trunc('month', current_date) + interval '1 month')::date - 1),
  'Az előző policy automatikusan lezárul a következő hónap előtt'
);
select is(
  (select count(*) from public.audit_logs where entity_type = 'user_pricing_policy' and entity_id = '00000000-0000-0000-0000-000000000822'),
  2::bigint,
  'Mindkét díjazási mód változás auditált'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000821', true);
select lives_ok(
  format(
    $$select public.admin_set_user_pricing_policy(
      '00000000-0000-0000-0000-000000000822', 'tiered', %L::date,
      '82000000-0000-0000-0000-000000000003')$$,
    (date_trunc('month', current_date) + interval '1 month')::date
  ),
  'A már tervezett jövőbeli mód ugyanazon kezdődátummal módosítható'
);
reset role;
select is(
  public.effective_user_pricing_scheme('00000000-0000-0000-0000-000000000822', (date_trunc('month', current_date) + interval '1 month')::date),
  'tiered'::public.user_pricing_scheme,
  'A jövőbeli mód módosítása érvényesül'
);
select is(
  (select count(*) from public.audit_logs where entity_type = 'user_pricing_policy' and entity_id = '00000000-0000-0000-0000-000000000822'),
  3::bigint,
  'A jövőbeli mód módosítása is auditált'
);

select * from finish();
rollback;
