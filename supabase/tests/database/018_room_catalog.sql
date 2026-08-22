begin;

select plan(4);

select is(
  (select count(*)::bigint from public.rooms where is_active),
  11::bigint,
  'Pontosan 11 aktív A-Hely helyiség van'
);

select is(
  (select array_agg(name order by display_order, name) from public.rooms where is_active),
  array[
    'Tréningterem',
    '1.Szoba-családi',
    '2.Szoba',
    '3.Szoba',
    '4.Szoba',
    '5.Szoba',
    '6.Szoba',
    'Gyerek szoba',
    'Pitypang szoba',
    'Csoport szoba',
    'Forrás tér'
  ]::text[],
  'Az aktív helyiségek neve és sorrendje megfelel a projekt baseline-nak'
);

select is(
  (select count(*)::bigint from public.rooms where name in ('5. Szoba', '6. Szoba')),
  0::bigint,
  'A régi szóközös 5./6. szobanevek nem maradnak meg'
);

select is(
  (select count(*)::bigint from public.rooms where is_training_room),
  1::bigint,
  'Pontosan egy Tréningterem van'
);

select * from finish();
rollback;
