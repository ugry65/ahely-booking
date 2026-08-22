begin;

-- Normalize the two legacy staging labels without changing room identities.
update public.rooms
set name = '5.Szoba',
    display_order = 6,
    is_active = true,
    is_training_room = false,
    updated_at = now()
where name = '5. Szoba';

update public.rooms
set name = '6.Szoba',
    display_order = 7,
    is_active = true,
    is_training_room = false,
    updated_at = now()
where name = '6. Szoba';

-- Ensure the complete A-Hely room catalog exists while preserving existing room IDs
-- and therefore all booking/permission references.
insert into public.rooms (name, display_order, is_training_room, is_active)
values
  ('Tréningterem', 1, true, true),
  ('1.Szoba-családi', 2, false, true),
  ('2.Szoba', 3, false, true),
  ('3.Szoba', 4, false, true),
  ('4.Szoba', 5, false, true),
  ('5.Szoba', 6, false, true),
  ('6.Szoba', 7, false, true),
  ('Gyerek szoba', 8, false, true),
  ('Pitypang szoba', 9, false, true),
  ('Csoport szoba', 10, false, true),
  ('Forrás tér', 11, false, true)
on conflict (name) do update set
  display_order = excluded.display_order,
  is_training_room = excluded.is_training_room,
  is_active = excluded.is_active,
  updated_at = now();

commit;
