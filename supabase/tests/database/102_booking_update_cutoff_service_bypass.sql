begin;

select plan(3);

-- Független review regresszió: a guard szándékos trusted service/internal bypassa
-- csak auth.uid() nélküli, privilegizált DB-kontextusra vonatkozik. A kliensoldali
-- authenticated/anon write határt külön RLS/EXECUTE tesztek védik.
select is(
  auth.uid(),
  null::uuid,
  'A service/internal bypass teszt valóban null auth.uid() kontextusban fut'
);

insert into auth.users (id, email, raw_user_meta_data) values (
  'b0000000-0000-0000-0000-000000000102',
  'cutoff-service-target@example.invalid',
  '{"first_name":"Service","last_name":"Target"}'
);

insert into public.bookings (
  id,
  room_id,
  user_id,
  created_by,
  start_at,
  end_at,
  idempotency_key,
  updated_at,
  note
) values (
  'b1000000-0000-0000-0000-000000000102',
  '11000000-0000-0000-0000-000000000002',
  'b0000000-0000-0000-0000-000000000102',
  'b0000000-0000-0000-0000-000000000102',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '13:00') at time zone 'Europe/Budapest',
  (((clock_timestamp() at time zone 'Europe/Budapest')::date + 10) + time '14:00') at time zone 'Europe/Budapest',
  'b2000000-0000-0000-0000-000000000102',
  date_trunc('second', clock_timestamp()),
  'service bypass eredeti'
);

-- Mesterségesen nagy cutoff: normál user ugyanilyen bookingot nem módosíthatna.
update public.app_settings
set value = '10000'::jsonb
where key = 'cancellation_cutoff_hours';

select lives_ok(
  $$
    update public.bookings
    set note = 'service bypass módosított',
        updated_at = date_trunc('second', clock_timestamp())
    where id = 'b1000000-0000-0000-0000-000000000102'
  $$,
  'Null auth.uid() trusted service/internal kontextusban a cutoff guard szándékosan bypassolható'
);

select is(
  (select note from public.bookings where id = 'b1000000-0000-0000-0000-000000000102'),
  'service bypass módosított',
  'A service/internal bypass módosítása ténylegesen eltárolódik'
);

select * from finish();
rollback;
