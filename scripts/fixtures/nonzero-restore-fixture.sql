\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('93000000-0000-0000-0000-000000000001', 'restore-admin@example.invalid', '{"first_name":"Restore","last_name":"Admin"}'),
  ('93000000-0000-0000-0000-000000000002', 'restore-user@example.invalid', '{"first_name":"Restore","last_name":"User"}');

update public.profiles
set role = 'admin'
where id = '93000000-0000-0000-0000-000000000001';

update public.profiles
set can_repeat_bookings = true
where id = '93000000-0000-0000-0000-000000000002';

insert into public.user_room_permissions (user_id, room_id, can_book, can_repeat) values
  ('93000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000002', true, true),
  ('93000000-0000-0000-0000-000000000002', '11000000-0000-0000-0000-000000000003', true, false);

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000002', true);
select public.create_booking_series(
  '11000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000002',
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '09:00') at time zone 'Europe/Budapest'),
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 3) + time '10:00') at time zone 'Europe/Budapest'),
  'daily',
  null,
  3,
  array[(clock_timestamp() at time zone 'Europe/Budapest')::date + 4],
  'abort_all',
  'individual',
  'Restore drill sorozat',
  '93000000-0000-0000-0000-000000000101'
);
reset role;

insert into public.bookings (
  id, room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key, booking_title
) values (
  '93000000-0000-0000-0000-000000000201',
  '11000000-0000-0000-0000-000000000003',
  '93000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000002',
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '13:00') at time zone 'Europe/Budapest'),
  ((((clock_timestamp() at time zone 'Europe/Budapest')::date + 2) + time '14:00') at time zone 'Europe/Budapest'),
  'individual',
  'active',
  '93000000-0000-0000-0000-000000000202',
  'Restore drill lemondás'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000002', true);
select public.cancel_booking(
  '93000000-0000-0000-0000-000000000201',
  'Restore drill lemondás',
  '93000000-0000-0000-0000-000000000203'
);
reset role;

insert into public.user_pricing_policies (
  user_id, pricing_scheme, valid_from, valid_to, created_by
) values (
  '93000000-0000-0000-0000-000000000002',
  'progressive',
  (date_trunc('month', current_date) - interval '1 month')::date,
  null,
  '93000000-0000-0000-0000-000000000001'
);

insert into public.bookings (
  room_id, user_id, created_by, start_at, end_at, use_type, status, idempotency_key, booking_title
)
select
  '11000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000002',
  (((date_trunc('month', current_date) - interval '1 month')::date + (g - 1))::text || ' 08:00 Europe/Budapest')::timestamptz,
  (((date_trunc('month', current_date) - interval '1 month')::date + (g - 1))::text || ' 10:00 Europe/Budapest')::timestamptz,
  'individual',
  'active',
  extensions.gen_random_uuid(),
  'Restore drill settlement'
from generate_series(1, 10) g;

set local role authenticated;
select set_config('request.jwt.claim.sub', '93000000-0000-0000-0000-000000000001', true);
select * from public.admin_close_monthly_settlement(
  '93000000-0000-0000-0000-000000000002',
  (date_trunc('month', current_date) - interval '1 month')::date
);
reset role;

commit;
