begin;

select plan(8);

select ok((select bool_and(calendar_color ~ '^#[0-9A-Fa-f]{6}$') from public.profiles),'Minden meglévő profil érvényes tartós naptárszínt kap');

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000181','color-admin@example.invalid','{"first_name":"Color","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000182','color-a@example.invalid','{"first_name":"Color","last_name":"A"}'),
 ('00000000-0000-0000-0000-000000000183','color-b@example.invalid','{"first_name":"Color","last_name":"B"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000181';

select isnt(
 (select calendar_color from public.profiles where id='00000000-0000-0000-0000-000000000182'),
 (select calendar_color from public.profiles where id='00000000-0000-0000-0000-000000000183'),
 'Két új user külön színt kap, amíg van szabad palettaszín'
);
select set_config('test.color_a',(select calendar_color from public.profiles where id='00000000-0000-0000-0000-000000000182'),false);
select set_config('test.color_b',(select calendar_color from public.profiles where id='00000000-0000-0000-0000-000000000183'),false);

insert into public.user_room_permissions(user_id,room_id,can_book,can_repeat) values
 ('00000000-0000-0000-0000-000000000182','11000000-0000-0000-0000-000000000002',true,false),
 ('00000000-0000-0000-0000-000000000183','11000000-0000-0000-0000-000000000002',true,false);

insert into public.bookings(room_id,user_id,created_by,start_at,end_at,status,idempotency_key) values
 ('11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000182','00000000-0000-0000-0000-000000000182','2026-09-10 09:00+02','2026-09-10 10:00+02','active','18100000-0000-0000-0000-000000000001'),
 ('11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000183','00000000-0000-0000-0000-000000000183','2026-09-10 10:00+02','2026-09-10 11:00+02','active','18100000-0000-0000-0000-000000000002');

update public.app_settings set value='true'::jsonb where key='show_other_booker_names';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select is(
 (select booker_color from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where not is_own limit 1),
 current_setting('test.color_b'),
 'Bekapcsolt névláthatóságnál más user tartós színe látható'
);
reset role;

update public.app_settings set value='false'::jsonb where key='show_other_booker_names';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000182',true);
select is((select booker_color from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where not is_own limit 1),null::text,'Kikapcsolt névláthatóságnál más user színe sem szivárog ki');
select is((select booker_display_name from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where not is_own limit 1),null::text,'Kikapcsolt névláthatóságnál más user neve sem látszik');
select is((select booker_color from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where is_own limit 1),current_setting('test.color_a'),'A saját foglalás színe névláthatóságtól függetlenül látható');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000181',true);
select is((select count(*)::bigint from public.list_calendar_bookings('2026-09-10 00:00+02','2026-09-11 00:00+02') where booker_color is not null),2::bigint,'Admin minden foglalás színét látja');
reset role;

select is((select calendar_color from public.profiles where id='00000000-0000-0000-0000-000000000182'),current_setting('test.color_a'),'A user színe tartós profiladat');

select * from finish();
rollback;
