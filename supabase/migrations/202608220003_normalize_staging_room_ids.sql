begin;

-- One-time repair for staging environments where the catalog migration was
-- previously applied before canonical IDs were added. These six rooms were
-- verified to have no booking, permission or rate references before this repair.
update public.rooms set id = '11000000-0000-0000-0000-000000000006' where name = '5.Szoba' and id <> '11000000-0000-0000-0000-000000000006';
update public.rooms set id = '11000000-0000-0000-0000-000000000007' where name = '6.Szoba' and id <> '11000000-0000-0000-0000-000000000007';
update public.rooms set id = '11000000-0000-0000-0000-000000000008' where name = 'Gyerek szoba' and id <> '11000000-0000-0000-0000-000000000008';
update public.rooms set id = '11000000-0000-0000-0000-000000000009' where name = 'Pitypang szoba' and id <> '11000000-0000-0000-0000-000000000009';
update public.rooms set id = '11000000-0000-0000-0000-000000000010' where name = 'Csoport szoba' and id <> '11000000-0000-0000-0000-000000000010';
update public.rooms set id = '11000000-0000-0000-0000-000000000011' where name = 'Forrás tér' and id <> '11000000-0000-0000-0000-000000000011';

commit;
