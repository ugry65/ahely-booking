begin;

update public.rooms
set name = '5.Szoba', display_order = 6, is_active = true, is_training_room = false, updated_at = now()
where name = '5. Szoba';

update public.rooms
set name = '6.Szoba', display_order = 7, is_active = true, is_training_room = false, updated_at = now()
where name = '6. Szoba';

insert into public.rooms (id, name, display_order, is_training_room, is_active)
values
  ('11000000-0000-0000-0000-000000000001', 'Tréningterem', 1, true, true),
  ('11000000-0000-0000-0000-000000000002', '1.Szoba-családi', 2, false, true),
  ('11000000-0000-0000-0000-000000000003', '2.Szoba', 3, false, true),
  ('11000000-0000-0000-0000-000000000004', '3.Szoba', 4, false, true),
  ('11000000-0000-0000-0000-000000000005', '4.Szoba', 5, false, true),
  ('11000000-0000-0000-0000-000000000006', '5.Szoba', 6, false, true),
  ('11000000-0000-0000-0000-000000000007', '6.Szoba', 7, false, true),
  ('11000000-0000-0000-0000-000000000008', 'Gyerek szoba', 8, false, true),
  ('11000000-0000-0000-0000-000000000009', 'Pitypang szoba', 9, false, true),
  ('11000000-0000-0000-0000-000000000010', 'Csoport szoba', 10, false, true),
  ('11000000-0000-0000-0000-000000000011', 'Forrás tér', 11, false, true)
on conflict (id) do update set
  name = excluded.name,
  display_order = excluded.display_order,
  is_training_room = excluded.is_training_room,
  is_active = excluded.is_active,
  updated_at = now();

commit;
