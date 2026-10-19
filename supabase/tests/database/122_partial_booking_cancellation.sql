begin;
select no_plan();
select set_config('test.parts_date',(timezone('Europe/Budapest',now())::date+2)::text,true);
select set_config('test.parts_month',date_trunc('month',current_setting('test.parts_date')::date)::date::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-0000-0000-000000000501','parts-admin@example.invalid','{"first_name":"Parts","last_name":"Admin"}'),
('00000000-0000-0000-0000-000000000502','parts-owner@example.invalid','{"first_name":"Parts","last_name":"Owner"}'),
('00000000-0000-0000-0000-000000000503','parts-other@example.invalid','{"first_name":"Parts","last_name":"Other"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000501';
insert into public.user_room_permissions(user_id,room_id,can_book) values('00000000-0000-0000-0000-000000000502','11000000-0000-0000-0000-000000000002',true);
-- Put the old block start inside the configured cutoff, but 10:00 outside it,
-- independently of the CI runner's wall-clock hour.
update public.app_settings set value=to_jsonb(ceil(extract(epoch from(timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '08:00')-now()))/3600)::integer+1)
where key='cancellation_cutoff_hours';
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason)
values('41000000-0000-0000-0000-000000000501','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000501',
timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '08:00'),timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '15:00'),'individual','active',gen_random_uuid(),2000,'00000000-0000-0000-0000-000000000501',now(),'Fixture');
select set_config('test.parts_version',(select updated_at::text from public.bookings where id='41000000-0000-0000-0000-000000000501'),true);
create function pg_temp.parts(p_key uuid,p_start time default '10:00',p_end time default '12:00',p_booking uuid default '41000000-0000-0000-0000-000000000501',p_version timestamptz default null)
returns uuid[] language sql security definer set search_path='' as $$
select public.cancel_booking_parts(p_booking,coalesce(p_version,current_setting('test.parts_version')::timestamptz),
jsonb_build_array(jsonb_build_object('start',timezone('Europe/Budapest',current_setting('test.parts_date')::date+p_start),'end',timezone('Europe/Budapest',current_setting('test.parts_date')::date+p_end))),'Selected hours',p_key);
$$;
select ok(not has_function_privilege('anon','public.cancel_booking_parts(uuid,timestamptz,jsonb,text,uuid)','EXECUTE'),'Anon denied');
select ok(not has_table_privilege('authenticated','public.booking_partial_cancellations','INSERT'),'No direct ledger writes');
select ok(not has_function_privilege('authenticated','public.admin_record_booking_payment_single(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid)','EXECUTE'),'Financial base stays private');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000503',true);
select throws_ok($$select pg_temp.parts(gen_random_uuid())$$,'42501',null,'Other user cannot delete own-looking ranges');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000501',true);
select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000501',14000,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000501');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000502',true);
select throws_ok($$select public.cancel_booking_scope('41000000-0000-0000-0000-000000000501','occurrence',null,gen_random_uuid())$$,'P0001',null,'Whole-booking cutoff not relaxed');
select throws_ok($$select pg_temp.parts(gen_random_uuid(),'08:00','09:00')$$,'P0001',null,'Early selected hour protected');
select throws_ok($$select pg_temp.parts(gen_random_uuid(),'10:30','14:30')$$,'P0001',null,'Half-hour remainder rejected');
select throws_ok($$select pg_temp.parts(gen_random_uuid(),'10:00:00.1','12:00')$$,'22023',null,'Fractional time-grid bypass rejected');
select lives_ok($$select pg_temp.parts('51000000-0000-0000-0000-000000000502')$$,'Later hours cancel even though whole block is inside cutoff');
select lives_ok($$select pg_temp.parts('51000000-0000-0000-0000-000000000502')$$,'Exact retry returns same result');
select throws_ok($$select pg_temp.parts('51000000-0000-0000-0000-000000000502','11:00','12:00')$$,'P0001',null,'Altered replay rejected');
select throws_ok($$select pg_temp.parts(gen_random_uuid())$$,'P0001',null,'Stale version rejected');
reset role;
select is((select (end_at at time zone 'Europe/Budapest')::time from public.bookings where id='41000000-0000-0000-0000-000000000501'),'10:00'::time,'Original ID retains first surviving fragment');
select is((select count(*) from public.bookings where root_booking_id='41000000-0000-0000-0000-000000000501'),1::bigint,'One additional surviving fragment');
select is((select sum(extract(epoch from(end_at-start_at)))::bigint/3600 from public.bookings where id='41000000-0000-0000-0000-000000000501' or root_booking_id='41000000-0000-0000-0000-000000000501'),5::bigint,'Only five booked hours remain');
select set_config('test.parts_child',(select id::text from public.bookings where root_booking_id='41000000-0000-0000-0000-000000000501'),true);
select is((select count(*) from public.booking_partial_cancellations),1::bigint,'Replay produced one immutable cancellation event');
select is((select count(*) from public.outbox_events where event_type='booking.parts_cancelled' and aggregate_id='41000000-0000-0000-0000-000000000501'),1::bigint,'One semantic partial cancellation event');
select is((select hourly_rate_override_huf from public.bookings where id=current_setting('test.parts_child')::uuid),2000::bigint,'Child preserves rate override');
select throws_ok($$update public.bookings set start_at=start_at+interval '1 month',end_at=end_at+interval '1 month' where id=current_setting('test.parts_child')::uuid$$,'42501',null,'Child cannot leave money-linked month');
select throws_ok($$update public.bookings set root_booking_id=null where id=current_setting('test.parts_child')::uuid$$,'42501',null,'Lineage immutable');
select set_config('test.parts_version',(select updated_at::text from public.bookings where id='41000000-0000-0000-0000-000000000501'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000501',true);
select is((select amount_huf from public.admin_booking_payment_context(current_setting('test.parts_child')::uuid)),10000::bigint,'Every fragment context aggregates remaining charge');
select is((select paid_huf from public.admin_booking_payment_context(current_setting('test.parts_child')::uuid)),14000::bigint,'Actual receipt is preserved');
select is((select sum(paid_huf)::bigint from public.admin_booking_payment_totals(current_setting('test.parts_month')::date)),14000::bigint,'Detail/export money appears once only');
select is((select count(*) from public.admin_booking_payment_history(current_setting('test.parts_child')::uuid)),1::bigint,'Child sees shared payment history');
select is((select overpaid_huf from public.admin_monthly_booking_payment_summary(current_setting('test.parts_month')::date) where user_id='00000000-0000-0000-0000-000000000502'),4000::bigint,'Monthly overpayment recalculated');
select is((select total_bookings from public.admin_cancellation_summary(current_setting('test.parts_month')::date,1) where user_id='00000000-0000-0000-0000-000000000502'),1::bigint,'Split does not inflate original booking count');
select is((select cancelled_hours from public.admin_cancellation_summary(current_setting('test.parts_month')::date,1) where user_id='00000000-0000-0000-0000-000000000502'),2::numeric,'Report counts removed hours not the whole original block');
select is((select cancelled_hours from public.admin_cancellation_details(current_setting('test.parts_month')::date,1,'00000000-0000-0000-0000-000000000502')),2::numeric,'Detail reports exact removed interval');
select lives_ok($$select pg_temp.parts(gen_random_uuid(),'08:00','10:00')$$,'Admin can cancel the first remaining fragment');
select lives_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000501',100,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000503')$$,'Cancelled root with active child still accepts grouped receipt');
select lives_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000501',14000,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000501')$$,'Original receipt replay survives fragmentation and root cancellation');
reset role;
select is((select count(*) from public.payments),2::bigint,'No copied or reassigned receipts');
select * from finish();
rollback;
