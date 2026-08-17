begin;

select plan(5);

select is(
  (
    select count(*)
    from public.pricing_tiers
    where 930 between min_minutes and coalesce(max_minutes, 2147483647)
      and date '2026-08-17' between valid_from and coalesce(valid_to, 'infinity'::date)
  ),
  1::bigint,
  '15,5 óra pontosan egy aktív díjsávba esik'
);

select is(
  (
    select count(*)
    from public.pricing_tiers
    where 3630 between min_minutes and coalesce(max_minutes, 2147483647)
      and date '2026-08-17' between valid_from and coalesce(valid_to, 'infinity'::date)
  ),
  1::bigint,
  '60,5 óra pontosan egy aktív díjsávba esik'
);

select ok(
  not exists (
    select 1
    from generate_series(60, 20000) as candidate(minutes)
    where not exists (
      select 1
      from public.pricing_tiers
      where candidate.minutes between min_minutes and coalesce(max_minutes, 2147483647)
        and date '2026-08-17' between valid_from and coalesce(valid_to, 'infinity'::date)
    )
  ),
  'Az induló díjsávok 60 perctől hézagmentesek'
);

select throws_ok(
  $$insert into public.pricing_tiers (
      min_minutes, max_minutes, hourly_rate_huf, valid_from
    ) values (
      900, 1200, 2500, date '2026-06-01'
    )$$,
  '23P01',
  null,
  'Átfedő idő- és perctartományú normál díjsáv nem hozható létre'
);

select throws_ok(
  $$insert into public.special_room_rates (
      room_id, use_type, hourly_rate_huf, valid_from
    ) values (
      '11000000-0000-0000-0000-000000000001',
      'group',
      5500,
      date '2027-01-01'
    )$$,
  '23P01',
  null,
  'Átfedő Tréningterem díjszabás nem hozható létre'
);

select * from finish();
rollback;
