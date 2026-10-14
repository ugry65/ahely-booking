begin;
select no_plan();
select set_config('test.correct_month',(date_trunc('month',timezone('Europe/Budapest',now()))-interval '1 month')::date::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000401','correction-admin@example.invalid','{"first_name":"Correction","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000402','correction-user@example.invalid','{"first_name":"Correction","last_name":"User"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000401';
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason)
values('41000000-0000-0000-0000-000000000401','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000401',
 timezone('Europe/Budapest',current_setting('test.correct_month')::date+8+time '08:00'),timezone('Europe/Budapest',current_setting('test.correct_month')::date+8+time '17:00'),'individual','active',gen_random_uuid(),2000,'00000000-0000-0000-0000-000000000401',now(),'Fixture');
select set_config('test.correct_version',(select updated_at::text from public.bookings where id='41000000-0000-0000-0000-000000000401'),true);
create function pg_temp.correct(p_key uuid,p_reason text,p_hour integer default 9,p_month date default null) returns uuid language sql security definer set search_path='' as $$
 select public.admin_correct_open_month_booking('41000000-0000-0000-0000-000000000401',current_setting('test.correct_version')::timestamptz,
 '11000000-0000-0000-0000-000000000002',timezone('Europe/Budapest',coalesce(p_month,current_setting('test.correct_month')::date)+8+make_time(p_hour,0,0)),
 timezone('Europe/Budapest',coalesce(p_month,current_setting('test.correct_month')::date)+8+time '17:00'),'individual',null,p_key,'Corrected booking',p_reason);
$$;
select ok(not has_function_privilege('anon','public.admin_correct_open_month_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,text)','EXECUTE'),'No anonymous correction');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000402',true);
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Forbidden')$$,'42501',null,'Normal user cannot correct historical booking');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000401',true);
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'')$$,'22023',null,'Reason required');
select set_config('test.correct_payment',public.admin_record_booking_payment('41000000-0000-0000-0000-000000000401',18000,current_date,'cash','cash_register',null,gen_random_uuid())::text,true);
select lives_ok($$select pg_temp.correct('51000000-0000-0000-0000-000000000401','One hour less')$$,'Admin changes 08-17 to 09-17 in open month');
select lives_ok($$select pg_temp.correct('51000000-0000-0000-0000-000000000401','One hour less')$$,'Exact retry with original stale version succeeds once');
select throws_ok($$select pg_temp.correct('51000000-0000-0000-0000-000000000401','Other reason')$$,'P0001',null,'Retry payload includes reason');
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Stale request')$$,'P0001',null,'New operation requires fresh booking version');
select is((select amount_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000401')),16000::bigint,'Corrected amount eight hours');
select is((select paid_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000401')),18000::bigint,'Actual paid money preserved');
select is((select overpaid_huf from public.admin_monthly_booking_payment_summary(current_setting('test.correct_month')::date) where user_id='00000000-0000-0000-0000-000000000402'),2000::bigint,'Monthly overpayment recalculated');
reset role;
select is((select hourly_rate_override_huf from public.bookings where id='41000000-0000-0000-0000-000000000401'),2000::bigint,'Hourly override unchanged');
select is((select count(*) from public.audit_logs where correlation_id='51000000-0000-0000-0000-000000000401' and action='booking.updated'),1::bigint,'One audited update for retry');
select is((select reason from public.audit_logs where correlation_id='51000000-0000-0000-0000-000000000401' and action='booking.updated'),'One hour less','Correction reason audited');
select is((select count(*) from public.outbox_events where aggregate_id='41000000-0000-0000-0000-000000000401' and event_type='booking.updated'),1::bigint,'One legacy update event');
select set_config('test.correct_version',(select updated_at::text from public.bookings where id='41000000-0000-0000-0000-000000000401'),true);
set local role authenticated;
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Invalid duration',17)$$,'P0001',null,'Existing duration validator enforced by new route');
reset role;
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000403','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000401',
 timezone('Europe/Budapest',current_setting('test.correct_month')::date+8+time '07:00'),timezone('Europe/Budapest',current_setting('test.correct_month')::date+8+time '08:00'),'individual','active',gen_random_uuid());
set local role authenticated;
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Overlap rejected',7)$$,'P0001',null,'Existing exclusion constraint enforced');
select is((select amount_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000401')),16000::bigint,'Rejected correction fully rolls back');
reset role;
insert into public.booking_series(id,owner_user_id,created_by,frequency,starts_on,occurrence_count,conflict_policy)
values('61000000-0000-0000-0000-000000000401','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000401','weekly',current_setting('test.correct_month')::date,2,'abort_all');
update public.bookings set series_id='61000000-0000-0000-0000-000000000401' where id='41000000-0000-0000-0000-000000000401';
insert into public.bookings(id,room_id,user_id,created_by,series_id,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000402','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000401','61000000-0000-0000-0000-000000000401',
 timezone('Europe/Budapest',current_setting('test.correct_month')::date+9+time '08:00'),timezone('Europe/Budapest',current_setting('test.correct_month')::date+9+time '09:00'),'individual','active',gen_random_uuid());
set local role authenticated;
select lives_ok($$select pg_temp.correct(gen_random_uuid(),'Single historical series occurrence',10)$$,'Historical series occurrence editable alone');
reset role;
select is((select extract(epoch from (end_at-start_at))::integer/60 from public.bookings where id='41000000-0000-0000-0000-000000000402'),60,'Other occurrence unchanged');
select is((select series_id::text from public.bookings where id='41000000-0000-0000-0000-000000000401'),'61000000-0000-0000-0000-000000000401','Series identity preserved');
select set_config('test.correct_version',(select updated_at::text from public.bookings where id='41000000-0000-0000-0000-000000000401'),true);
select * from public.admin_create_monthly_settlement_revision('00000000-0000-0000-0000-000000000401',(current_setting('test.correct_month')::date-interval '1 month')::date,'Legacy partial-close fixture',gen_random_uuid());
update public.monthly_settlements ms set is_closed=true,closed_at=now(),closed_by='00000000-0000-0000-0000-000000000401',
 closed_revision_id=(select sr.id from public.settlement_revisions sr where sr.settlement_id=ms.id order by sr.revision_number desc limit 1)
where ms.user_id='00000000-0000-0000-0000-000000000401' and ms.settlement_month=(current_setting('test.correct_month')::date-interval '1 month')::date;
set local role authenticated;
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Target legacy closure',10,(current_setting('test.correct_month')::date-interval '1 month')::date)$$,'42501',null,'Target legacy partial closure cannot be entered');
select lives_ok($$select * from public.admin_close_monthly_settlement_period(current_setting('test.correct_month')::date)$$,'Close month normally');
select throws_ok($$select pg_temp.correct(gen_random_uuid(),'Forbidden after closure',11)$$,'42501',null,'Published source closure enforced');
select is((select paid_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000401')),18000::bigint,'Close did not change receipts');
reset role;
select * from finish();
rollback;
