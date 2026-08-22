begin;
select plan(14);

select has_function('public','admin_monthly_active_booking_details',array['date','uuid'],'A tételes aktív elszámolási riport létezik');
select has_function('public','admin_cancellation_summary',array['date','integer'],'A lemondási összesítő riport létezik');
select has_function('public','admin_cancellation_details',array['date','integer','uuid'],'A tételes lemondási riport létezik');

insert into auth.users (id,email,raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000221','report-admin@example.invalid','{"first_name":"Riport","last_name":"Admin"}'),
  ('00000000-0000-0000-0000-000000000222','report-user@example.invalid','{"first_name":"Teszt","last_name":"User"}'),
  ('00000000-0000-0000-0000-000000000223','report-admin2@example.invalid','{"first_name":"Másik","last_name":"Admin"}');
update public.profiles set role='admin' where id in ('00000000-0000-0000-0000-000000000221','00000000-0000-0000-0000-000000000223');

insert into public.bookings (id,room_id,user_id,created_by,start_at,end_at,status,idempotency_key) values
  ('22000000-0000-0000-0000-000000000221','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000222','2027-02-02 09:00+01','2027-02-02 10:00+01','active','23000000-0000-0000-0000-000000000221'),
  ('22000000-0000-0000-0000-000000000222','11000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000222','2027-02-03 10:00+01','2027-02-03 11:30+01','active','23000000-0000-0000-0000-000000000222'),
  ('22000000-0000-0000-0000-000000000223','11000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000222','2027-02-04 12:00+01','2027-02-04 13:00+01','cancelled','23000000-0000-0000-0000-000000000223'),
  ('22000000-0000-0000-0000-000000000224','11000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000222','00000000-0000-0000-0000-000000000222','2027-02-05 14:00+01','2027-02-05 16:00+01','cancelled','23000000-0000-0000-0000-000000000224');

insert into public.booking_cancellations (booking_id,cancelled_by,cancelled_at,minutes_before_start,reason,original_snapshot,idempotency_key,settlement_excluded) values
  ('22000000-0000-0000-0000-000000000223','00000000-0000-0000-0000-000000000222','2027-02-03 12:00+01',1440,'user törölte','{}'::jsonb,'24000000-0000-0000-0000-000000000223',true),
  ('22000000-0000-0000-0000-000000000224','00000000-0000-0000-0000-000000000223','2027-02-04 14:00+01',1440,'admin törölte','{}'::jsonb,'24000000-0000-0000-0000-000000000224',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000222',true);
select throws_ok($$select * from public.admin_monthly_active_booking_details('2027-02-01',null)$$,'42501','Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.','Normál user nem olvashat elszámolási részleteket');

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000221',true);
select is((select count(*) from public.admin_monthly_active_booking_details('2027-02-15',null)),2::bigint,'A tételes elszámolásból a lemondott foglalások kimaradnak');
select is((select sum(total_minutes) from public.admin_monthly_active_booking_details('2027-02-01','00000000-0000-0000-0000-000000000222')),150::numeric,'Az aktív foglalások tételes összege 150 perc');
select is((select total_bookings from public.admin_cancellation_summary('2027-02-01',1)),4::bigint,'A lemondási nevező minden eredeti aktív vagy lemondott foglalást tartalmaz');
select is((select cancelled_count from public.admin_cancellation_summary('2027-02-01',1)),2::bigint,'Az összes lemondott foglalás külön számlálható');
select is((select cancelled_hours from public.admin_cancellation_summary('2027-02-01',1)),3.00::numeric,'Az összes lemondott idő 3 óra');
select is((select user_cancelled_count from public.admin_cancellation_summary('2027-02-01',1)),1::bigint,'Admin által törölt foglalás nem számít user saját lemondásának');
select is((select cancellation_rate from public.admin_cancellation_summary('2027-02-01',1)),25.0::numeric,'A user lemondási aránya 1 saját törlés / 4 összes foglalás = 25%');
select is((select count(*) from public.admin_cancellation_details('2027-02-01',1,null)),2::bigint,'A tételes lemondási lista minden lemondott foglalást tartalmaz');
select is((select count(*) from public.admin_cancellation_details('2027-02-01',1,null) where cancelled_by_user),1::bigint,'A tételes lista megkülönbözteti a user és admin lemondást');
select throws_ok($$select * from public.admin_cancellation_summary('2027-02-01',2)$$,'22023','Az időszak csak 1, 3, 6 vagy 12 hónap lehet.','Érvénytelen időszak fail-closed módon elutasított');

reset role;
select * from finish();
rollback;
