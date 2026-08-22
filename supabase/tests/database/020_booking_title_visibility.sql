begin;

select plan(3);

insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000121','title-admin@example.invalid','{"first_name":"Title","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000122','title-owner@example.invalid','{"first_name":"Title","last_name":"Owner"}'),
 ('00000000-0000-0000-0000-000000000123','title-viewer@example.invalid','{"first_name":"Title","last_name":"Viewer"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000121';
insert into public.user_room_permissions(user_id,room_id,can_book) values
 ('00000000-0000-0000-0000-000000000122','11000000-0000-0000-0000-000000000008',true),
 ('00000000-0000-0000-0000-000000000123','11000000-0000-0000-0000-000000000008',true);
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,idempotency_key,booking_title) values
 ('24000000-0000-0000-0000-000000000121','11000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000122','00000000-0000-0000-0000-000000000122','2026-10-15 09:00:00+02','2026-10-15 10:00:00+02','24000000-0000-0000-0000-000000000121','Bizalmas konzultáció');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000123',true);
select is((select booking_title from public.list_calendar_bookings('2026-10-15 00:00+02','2026-10-16 00:00+02') where booking_id='24000000-0000-0000-0000-000000000121'),null,'Más normál user nem kapja meg a foglalás címét');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000122',true);
select is((select booking_title from public.list_calendar_bookings('2026-10-15 00:00+02','2026-10-16 00:00+02') where booking_id='24000000-0000-0000-0000-000000000121'),'Bizalmas konzultáció','A tulajdonos látja a saját foglalás címét');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000121',true);
select is((select booking_title from public.list_calendar_bookings('2026-10-15 00:00+02','2026-10-16 00:00+02') where booking_id='24000000-0000-0000-0000-000000000121'),'Bizalmas konzultáció','Admin látja más user foglalásának címét');

reset role;
select * from finish();
rollback;
