-- Synthetic fixtures only; all writes roll back. Staging only.
begin;
select set_config('test.parts_admin',gen_random_uuid()::text,true),set_config('test.parts_owner',gen_random_uuid()::text,true),
set_config('test.parts_room',gen_random_uuid()::text,true),set_config('test.parts_root',gen_random_uuid()::text,true),
set_config('test.parts_date',(timezone('Europe/Budapest',now())::date+2)::text,true);
insert into auth.users(id,email,raw_user_meta_data) values
(current_setting('test.parts_admin')::uuid,current_setting('test.parts_admin')||'@example.invalid','{"first_name":"Parts smoke","last_name":"Admin"}'),
(current_setting('test.parts_owner')::uuid,current_setting('test.parts_owner')||'@example.invalid','{"first_name":"Parts smoke","last_name":"Owner"}');
update public.profiles set role='admin' where id=current_setting('test.parts_admin')::uuid;
insert into public.rooms(id,name,display_order) values(current_setting('test.parts_room')::uuid,'Partial smoke '||current_setting('test.parts_room'),9999);
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason)
values(current_setting('test.parts_root')::uuid,current_setting('test.parts_room')::uuid,current_setting('test.parts_owner')::uuid,current_setting('test.parts_admin')::uuid,
timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '08:00'),timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '15:00'),
'individual','active',gen_random_uuid(),2000,current_setting('test.parts_admin')::uuid,now(),'Synthetic rollback fixture');
select set_config('test.parts_version',(select updated_at::text from public.bookings where id=current_setting('test.parts_root')::uuid),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('test.parts_admin'),true);
select public.admin_record_booking_payment(current_setting('test.parts_root')::uuid,14000,current_date,'cash','cash_register',null,gen_random_uuid());
select set_config('request.jwt.claim.sub',current_setting('test.parts_owner'),true);
select public.cancel_booking_parts(current_setting('test.parts_root')::uuid,current_setting('test.parts_version')::timestamptz,
jsonb_build_array(jsonb_build_object('start',timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '10:00'),'end',timezone('Europe/Budapest',current_setting('test.parts_date')::date+time '12:00'))),'Staging smoke selected hours',gen_random_uuid());
select set_config('request.jwt.claim.sub',current_setting('test.parts_admin'),true);
do $$
declare c record; m record; v_paid bigint;
begin
 select * into strict c from public.admin_booking_payment_context(current_setting('test.parts_root')::uuid);
 if c.amount_huf is distinct from 10000::bigint or c.paid_huf is distinct from 14000::bigint then raise exception 'Group charge/receipt assertion failed'; end if;
 select sum(paid_huf)::bigint into v_paid from public.admin_booking_payment_totals(date_trunc('month',current_setting('test.parts_date')::date)::date) where payment_group_id=current_setting('test.parts_root')::uuid;
 if v_paid is distinct from 14000::bigint then raise exception 'Duplicated/missing export receipt'; end if;
 select * into strict m from public.admin_monthly_booking_payment_summary(date_trunc('month',current_setting('test.parts_date')::date)::date) where user_id=current_setting('test.parts_owner')::uuid;
 if m.overpaid_huf is distinct from 4000::bigint then raise exception 'Monthly overpayment assertion failed'; end if;
end $$;
reset role;
do $$
declare v_count bigint; v_minutes bigint;
begin
 select count(*),sum(extract(epoch from(end_at-start_at))/60)::bigint into v_count,v_minutes from public.bookings
 where id=current_setting('test.parts_root')::uuid or root_booking_id=current_setting('test.parts_root')::uuid;
 if v_count is distinct from 2::bigint or v_minutes is distinct from 300::bigint then raise exception 'Remaining fragments assertion failed'; end if;
end $$;
rollback;
select 'PASS: owner partial cancellation, five retained hours, unchanged 14000 receipt, group/export/month balance; fixtures rolled back' result;
