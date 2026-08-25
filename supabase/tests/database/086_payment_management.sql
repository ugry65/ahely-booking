begin;

select plan(16);

select has_function('public','admin_record_payment',array['uuid','date','bigint','date','payment_method','money_destination','text','uuid'],'Admin befizetés RPC létezik');
select has_function('public','admin_monthly_payment_summary',array['date'],'Admin havi befizetés összesítő RPC létezik');
select has_function('public','admin_payment_history',array['date'],'Admin tételes befizetési előzmény RPC létezik');

insert into auth.users (id, email, raw_user_meta_data) values
  ('86000000-0000-0000-0000-000000000001','payment-admin@example.invalid','{"first_name":"Payment","last_name":"Admin"}'),
  ('86000000-0000-0000-0000-000000000002','payment-user@example.invalid','{"first_name":"Payment","last_name":"User"}');
update public.profiles set role='admin' where id='86000000-0000-0000-0000-000000000001';

insert into public.bookings(room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values (
  '11000000-0000-0000-0000-000000000002',
  '86000000-0000-0000-0000-000000000002',
  '86000000-0000-0000-0000-000000000002',
  (((date_trunc('month', current_date)-interval '1 month')::date)::text || ' 09:00 Europe/Budapest')::timestamptz,
  (((date_trunc('month', current_date)-interval '1 month')::date)::text || ' 11:00 Europe/Budapest')::timestamptz,
  'individual','active',extensions.gen_random_uuid()
);

set local role authenticated;
select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000002',true);
select throws_ok(
  format($$select * from public.admin_record_payment('86000000-0000-0000-0000-000000000002',%L::date,2000,current_date,'cash','cash_register',null,extensions.gen_random_uuid())$$,(date_trunc('month',current_date)-interval '1 month')::date),
  '42501','Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.','Normál user nem rögzíthet befizetést'
);
select throws_ok(
  format($$select * from public.admin_payment_history(%L::date)$$,(date_trunc('month',current_date)-interval '1 month')::date),
  '42501','Ehhez a művelethez aktív adminisztrátori jogosultság szükséges.','Normál user nem olvashat tételes befizetéseket'
);

select set_config('request.jwt.claim.sub','86000000-0000-0000-0000-000000000001',true);
select lives_ok(
  format($$select * from public.admin_record_payment('86000000-0000-0000-0000-000000000002',%L::date,2000,current_date,'cash','cash_register','első részlet','86000000-0000-0000-0000-000000000010')$$,(date_trunc('month',current_date)-interval '1 month')::date),
  'Admin részfizetést rögzíthet'
);

select is((select paid_huf from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),2000::bigint,'Részfizetés összege 2000 Ft');
select is((select remaining_huf from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),3400::bigint,'Fennmaradó tartozás 3400 Ft');
select is((select payment_status from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),'partially_paid'::public.payment_status,'Részfizetés státusz helyes');

select lives_ok(
  format($$select * from public.admin_record_payment('86000000-0000-0000-0000-000000000002',%L::date,3400,current_date,'bank_transfer','teem_otp','második részlet','86000000-0000-0000-0000-000000000011')$$,(date_trunc('month',current_date)-interval '1 month')::date),
  'Második részfizetéssel teljesen kiegyenlíthető'
);
select is((select paid_huf from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),5400::bigint,'Teljes befizetés 5400 Ft');
select is((select remaining_huf from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),0::bigint,'Kintlévőség nulla');
select is((select payment_status from public.admin_monthly_payment_summary((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),'paid'::public.payment_status,'Teljes fizetés státusz Fizetve');
select is((select count(*) from public.admin_payment_history((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),2::bigint,'A tételes előzmény mindkét részfizetést mutatja');
select is((select sum(amount_huf)::bigint from public.admin_payment_history((date_trunc('month',current_date)-interval '1 month')::date) where user_id='86000000-0000-0000-0000-000000000002'),5400::bigint,'A tételes előzmény összege egyezik a befizetett összeggel');

select throws_ok(
  format($$select * from public.admin_record_payment('86000000-0000-0000-0000-000000000002',%L::date,1,current_date,'cash','cash_register',null,extensions.gen_random_uuid())$$,(date_trunc('month',current_date)-interval '1 month')::date),
  'P0001','A rögzített befizetés meghaladná a fennmaradó tartozást.','Túlfizetés nem rögzíthető véletlenül'
);
select is((select count(*) from public.audit_logs where action='payment.created' and after_data->>'user_id'='86000000-0000-0000-0000-000000000002'),2::bigint,'Mindkét befizetés auditált');

select * from finish();
rollback;
