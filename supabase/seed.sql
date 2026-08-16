insert into public.rooms (id, name, display_order, is_training_room) values
  ('11000000-0000-0000-0000-000000000001', 'Tréningterem', 1, true),
  ('11000000-0000-0000-0000-000000000002', '1.Szoba-családi', 2, false),
  ('11000000-0000-0000-0000-000000000003', '2.Szoba', 3, false),
  ('11000000-0000-0000-0000-000000000004', '3.Szoba', 4, false),
  ('11000000-0000-0000-0000-000000000005', '4.Szoba', 5, false),
  ('11000000-0000-0000-0000-000000000006', '5.Szoba', 6, false),
  ('11000000-0000-0000-0000-000000000007', '6.Szoba', 7, false),
  ('11000000-0000-0000-0000-000000000008', 'Gyerek szoba', 8, false),
  ('11000000-0000-0000-0000-000000000009', 'Pitypang szoba', 9, false),
  ('11000000-0000-0000-0000-000000000010', 'Csoport szoba', 10, false),
  ('11000000-0000-0000-0000-000000000011', 'Forrás tér', 11, false)
on conflict (id) do update set
  name = excluded.name,
  display_order = excluded.display_order,
  is_training_room = excluded.is_training_room;

insert into public.special_room_rates (
  id, room_id, use_type, hourly_rate_huf, valid_from
) values (
  '12000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  'group',
  5000,
  date '2026-01-01'
)
on conflict (room_id, use_type, valid_from) do update set
  hourly_rate_huf = excluded.hourly_rate_huf;
