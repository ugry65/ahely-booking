-- Synthetic fixtures only; every write rolls back. Run on staging only.
begin;
select set_config('test.actor',gen_random_uuid()::text,true),
       set_config('test.room',gen_random_uuid()::text,true),
       set_config('test.booking',gen_random_uuid()::text,true),
       set_config('test.month',date_trunc('month',timezone('Europe/Budapest',now()))::date::text,true);
insert into auth.users(id,email,raw_user_meta_data)
values(current_setting('test.actor')::uuid,current_setting('test.actor')||'@example.invalid','{"first_name":"Staging","last_name":"Correction smoke"}');
update public.profiles set role='admin',is_active=true where id=current_setting('test.actor')::uuid;
insert into public.rooms(id,name,display_order)
values(current_setting('test.room')::uuid,'Correction smoke '||current_setting('test.room'),9999);
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason)
values(current_setting('test.booking')::uuid,current_setting('test.room')::uuid,current_setting('test.actor')::uuid,current_setting('test.actor')::uuid,
 timezone('Europe/Budapest',current_setting('test.month')::date+time '08:00'),timezone('Europe/Budapest',current_setting('test.month')::date+time '17:00'),
 'individual','active',gen_random_uuid(),2000,current_setting('test.actor')::uuid,now(),'Synthetic fixture');
select set_config('test.version',(select updated_at::text from public.bookings where id=current_setting('test.booking')::uuid),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.actor'),true);
select public.admin_record_booking_payment(current_setting('test.booking')::uuid,18000,current_date,'cash','cash_register',null,gen_random_uuid());
select public.admin_correct_open_month_booking(current_setting('test.booking')::uuid,current_setting('test.version')::timestamptz,
 current_setting('test.room')::uuid,timezone('Europe/Budapest',current_setting('test.month')::date+time '09:00'),
 timezone('Europe/Budapest',current_setting('test.month')::date+time '17:00'),'individual',null,gen_random_uuid(),'Synthetic correction','One hour less; staging rollback smoke');
do $$
declare c record; s record;
begin
 select * into strict c from public.admin_booking_payment_context(current_setting('test.booking')::uuid);
 if c.amount_huf is distinct from 16000::bigint or c.paid_huf is distinct from 18000::bigint then raise exception 'Correction/payment context mismatch'; end if;
 select * into strict s from public.admin_monthly_booking_payment_summary(current_setting('test.month')::date) where user_id=current_setting('test.actor')::uuid;
 if s.overpaid_huf is distinct from 2000::bigint then raise exception 'Monthly overpayment mismatch'; end if;
end $$;
reset role;
rollback;
select 'PASS: historical correction, receipt preservation, monthly overpayment; all fixtures rolled back' as result;
