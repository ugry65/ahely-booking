begin;

select plan(6);

insert into auth.users (id, email, raw_user_meta_data) values
  ('92000000-0000-0000-0000-000000000001', 'timeline-admin@example.com', '{"first_name":"Timeline","last_name":"Admin"}'::jsonb),
  ('92000000-0000-0000-0000-000000000002', 'timeline-user@example.com', '{"first_name":"Timeline","last_name":"User"}'::jsonb);

update public.profiles set role = 'admin' where id = '92000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '92000000-0000-0000-0000-000000000001', true);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'user_price_override_no_overlap'
      and contype = 'x'
      and conrelid = 'public.user_price_overrides'::regclass
  ),
  'A Fix óradíj időintervallumokat adatbázis exclusion constraint védi az átfedéstől'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '92000000-0000-0000-0000-000000000002', 'fixed', 1500, date '2027-06-01', gen_random_uuid()
  )$$,
  'Jövőbeli Fix díj előre ütemezhető'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '92000000-0000-0000-0000-000000000002', 'progressive', null, date '2027-03-01', gen_random_uuid()
  )$$,
  'Korábbi hónaptól Progresszív mód külön ütemezhető'
);

select is(
  (select hourly_rate_huf from public.user_price_overrides
    where user_id = '92000000-0000-0000-0000-000000000002'
      and date '2027-06-01' between valid_from and coalesce(valid_to, 'infinity'::date)
    order by valid_from desc limit 1),
  1500::bigint,
  'A későbbre korábban ütemezett Fix terv megmarad a saját kezdőhónapjára'
);

select lives_ok(
  $$select public.admin_set_user_pricing_configuration(
    '92000000-0000-0000-0000-000000000002', 'fixed', 1800, date '2027-06-01', gen_random_uuid()
  )$$,
  'Azonos jövőbeli kezdőhónap Fix díja módosítható'
);

select is(
  (select hourly_rate_huf from public.user_price_overrides
    where user_id = '92000000-0000-0000-0000-000000000002'
      and valid_from = date '2027-06-01'),
  1800::bigint,
  'Az azonos kezdőhónapú Fix terv az új értékre frissül'
);

select * from finish();
rollback;
