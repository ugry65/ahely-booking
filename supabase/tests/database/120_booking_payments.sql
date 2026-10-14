begin;
select no_plan();
select set_config('test.payment_month',(date_trunc('month',timezone('Europe/Budapest',now()))-interval '1 month')::date::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000391','payment-admin@example.invalid','{"first_name":"Payment","last_name":"Admin"}'),
 ('00000000-0000-0000-0000-000000000392','payment-user@example.invalid','{"first_name":"Payment","last_name":"User"}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-000000000391';
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000391','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000392','00000000-0000-0000-0000-000000000391',
 timezone('Europe/Budapest',current_setting('test.payment_month')::date+1+time '07:00'),timezone('Europe/Budapest',current_setting('test.payment_month')::date+1+time '08:00'),'individual','active',gen_random_uuid());
select ok(not has_table_privilege('authenticated','public.payment_voids','SELECT'),'Void ledger is not exposed');
select ok(not has_function_privilege('anon','public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid)','EXECUTE'),'Anonymous cannot record money');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000392',true);
select throws_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',1000,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000391')$$,'42501',null,'User cannot mark paid');
select throws_ok($$select * from public.admin_booking_payment_history('41000000-0000-0000-0000-000000000391')$$,'42501',null,'User cannot read other financial data');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000391',true);
select is((select paid_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000391')),0::bigint,'Initially unpaid');
select throws_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',0,current_date,'cash','cash_register',null,gen_random_uuid())$$,'22023',null,'Reject zero');
select throws_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',1,current_date+1,'cash','cash_register',null,gen_random_uuid())$$,'22023',null,'Reject future receipt date');
select set_config('test.payment_id',public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',1000,current_date,'cash','cash_register','Envelope','51000000-0000-0000-0000-000000000391')::text,true);
select is(public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',1000,current_date,'cash','cash_register','Envelope','51000000-0000-0000-0000-000000000391')::text,current_setting('test.payment_id'),'Retry returns same receipt');
select throws_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',1001,current_date,'cash','cash_register','Envelope','51000000-0000-0000-0000-000000000391')$$,'P0001',null,'Reject reused key with different payload');
select is((select paid_huf from public.admin_monthly_payment_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),1000::bigint,'Monthly ledger counts one receipt once');
select lives_ok($$select public.admin_void_booking_payment(current_setting('test.payment_id')::uuid,'Wrong receipt')$$,'Void wrong entry');
select lives_ok($$select public.admin_void_booking_payment(current_setting('test.payment_id')::uuid,'Wrong receipt')$$,'Void retry is idempotent');
select is((select paid_huf from public.admin_monthly_payment_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),0::bigint,'Existing summary excludes void');
select lives_ok($$select * from public.admin_record_payment('00000000-0000-0000-0000-000000000392',current_setting('test.payment_month')::date,1000,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000393')$$,'Legacy monthly payment writer permits replacement after void');
select lives_ok($$select * from public.admin_create_monthly_settlement_revision('00000000-0000-0000-0000-000000000392',current_setting('test.payment_month')::date,'Draft',gen_random_uuid())$$,'Create open-month draft snapshot');
reset role;
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000392','11000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000392','00000000-0000-0000-0000-000000000391',
 timezone('Europe/Budapest',current_setting('test.payment_month')::date+2+time '07:00'),timezone('Europe/Budapest',current_setting('test.payment_month')::date+2+time '08:00'),'individual','active',gen_random_uuid());
set local role authenticated;
select ok((select amount_huf>0 from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000392')),'New booking after draft uses live rate');
select is((select booking_count from public.admin_payment_pricing_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),2::bigint,'Financial export includes bookings added after draft');
select is((select count(*) from public.admin_payment_pricing_details(current_setting('test.payment_month')::date,'00000000-0000-0000-0000-000000000392')),2::bigint,'Financial details include new open-month booking');
select is((select due_huf from public.admin_monthly_booking_payment_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),(select amount_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000391'))+(select amount_huf from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000392')),'Open monthly payment balance is live');
select lives_ok($$select public.admin_record_booking_payment('41000000-0000-0000-0000-000000000391',100000,current_date,'cash','cash_register',null,'51000000-0000-0000-0000-000000000394')$$,'Actual receipt can exceed preliminary due');
select ok((select overpaid_huf>0 from public.admin_monthly_booking_payment_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),'Overpayment reported separately');
reset role;
select throws_ok($$update public.bookings set user_id='00000000-0000-0000-0000-000000000391' where id='41000000-0000-0000-0000-000000000391'$$,'P0001',null,'No silent reassignment of allocated money');
select throws_ok($$update public.payments set amount_huf=1 where id=current_setting('test.payment_id')::uuid$$,'42501',null,'Receipt immutable');
select throws_ok($$delete from public.payments where id=current_setting('test.payment_id')::uuid$$,'42501',null,'Receipt cannot be deleted');
select throws_ok($$delete from public.payment_voids where payment_id=current_setting('test.payment_id')::uuid$$,'42501',null,'Void cannot be deleted');
set local role authenticated;
select lives_ok($$select * from public.admin_close_monthly_settlement_period(current_setting('test.payment_month')::date)$$,'Closing preserves receipt ledger');
select is((select is_closed from public.admin_booking_payment_context('41000000-0000-0000-0000-000000000391')),true,'Closed context identifies final fee');
select is((select count(*) from public.admin_booking_payment_history('41000000-0000-0000-0000-000000000391')),2::bigint,'History preserves void and valid receipt');
select is((select paid_huf from public.admin_monthly_booking_payment_summary(current_setting('test.payment_month')::date) where user_id='00000000-0000-0000-0000-000000000392'),101000::bigint,'Close does not erase paid money');
reset role;
select ok(exists(select 1 from public.audit_logs where entity_id=current_setting('test.payment_id') and action='booking_payment.created'),'Receipt audit exists');
select ok(exists(select 1 from public.audit_logs where entity_id=current_setting('test.payment_id') and action='booking_payment.voided'),'Void audit exists');
select * from finish();
rollback;
