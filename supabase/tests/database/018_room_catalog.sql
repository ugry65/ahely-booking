begin;

select plan(5);
select is((select count(*)::bigint from public.rooms where is_active),11::bigint,'Pontosan 11 aktív A-Hely helyiség van');
select is((select array_agg(name order by display_order,name) from public.rooms where is_active),array['Tréningterem','1.Szoba-családi','2.Szoba','3.Szoba','4.Szoba','5.Szoba','6.Szoba','Gyerek szoba','Pitypang szoba','Csoport szoba','Forrás tér']::text[],'Az aktív helyiségek neve és sorrendje megfelel a projekt baseline-nak');
select is((select array_agg(id order by display_order) from public.rooms where is_active),array['11000000-0000-0000-0000-000000000001'::uuid,'11000000-0000-0000-0000-000000000002'::uuid,'11000000-0000-0000-0000-000000000003'::uuid,'11000000-0000-0000-0000-000000000004'::uuid,'11000000-0000-0000-0000-000000000005'::uuid,'11000000-0000-0000-0000-000000000006'::uuid,'11000000-0000-0000-0000-000000000007'::uuid,'11000000-0000-0000-0000-000000000008'::uuid,'11000000-0000-0000-0000-000000000009'::uuid,'11000000-0000-0000-0000-000000000010'::uuid,'11000000-0000-0000-0000-000000000011'::uuid],'A helyiségek stabil kanonikus azonosítókat használnak');
select is((select count(*)::bigint from public.rooms where name in ('5. Szoba','6. Szoba')),0::bigint,'A régi szóközös 5./6. szobanevek nem maradnak meg');
select is((select count(*)::bigint from public.rooms where is_training_room),1::bigint,'Pontosan egy Tréningterem van');
select * from finish();
rollback;
