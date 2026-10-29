begin;
select plan(8);

-- Actual application schema/resolver/calculator; every fixture is rolled back.
alter table public.bookings add column group_hourly_rate_huf bigint
  check(group_hourly_rate_huf is null or group_hourly_rate_huf>=0);
create or replace function public.apply_training_group_booking_rate()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_is_training boolean;
begin
  select r.is_training_room into v_is_training from public.rooms r where r.id=new.room_id;
  if coalesce(v_is_training,false) and new.use_type='group' then
    if new.group_hourly_rate_huf is null then new.group_hourly_rate_huf:=5000; end if;
  else new.group_hourly_rate_huf:=null;
  end if;
  return new;
end $$;
create trigger bookings_training_group_rate_default before insert or update of
room_id,use_type,group_hourly_rate_huf on public.bookings for each row
execute function public.apply_training_group_booking_rate();

insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-0000-0000-000000000192','parity@example.invalid',
'{"first_name":"Synthetic","last_name":"Parity"}');
insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000192','11000000-0000-0000-0000-000000000001',
'00000000-0000-0000-0000-000000000192','00000000-0000-0000-0000-000000000192',
'2035-10-15 09:00+02','2035-10-15 10:00+02','group','active',gen_random_uuid());
select is((select group_hourly_rate_huf from public.bookings where id='41000000-0000-0000-0000-000000000192'),5000::bigint,
  'Faithful legacy trigger reproduces historical automatic 5000');
create temp table parity_before as select to_jsonb(b) as row from public.bookings b;
create temp table parity_function_before as select md5(prosrc) as hash,proacl::text as acl
from pg_proc where oid='public.resolve_booking_applied_rate(uuid,integer)'::regprocedure;

-- Same operation as the versioned migration, inside this rollback transaction.
set local lock_timeout='3s';
drop trigger bookings_training_group_rate_default on public.bookings;
select ok(not exists((select to_jsonb(b) from public.bookings b except select row from parity_before)
union all(select row from parity_before except select to_jsonb(b) from public.bookings b)),
  'Trigger removal preserves every existing booking byte-for-byte');
update public.special_room_rates set hourly_rate_huf=6200
where room_id='11000000-0000-0000-0000-000000000001' and use_type='group'
and date '2035-10-01' between valid_from and coalesce(valid_to,'infinity'::date);

insert into public.bookings(id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key)
values('41000000-0000-0000-0000-000000000193','11000000-0000-0000-0000-000000000001',
'00000000-0000-0000-0000-000000000192','00000000-0000-0000-0000-000000000192',
'2035-10-16 09:00+02','2035-10-16 10:00+02','group','active',gen_random_uuid());
select is((select group_hourly_rate_huf from public.bookings where id='41000000-0000-0000-0000-000000000193'),null::bigint,
  'New group booking has no legacy default');
select is((select hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000193',0)),6200::bigint,
  'Actual resolver uses configured training tariff for new booking');
select is((select hourly_rate_huf from public.resolve_booking_applied_rate('41000000-0000-0000-0000-000000000192',0)),5000::bigint,
  'Actual resolver preserves historical booking rate');
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000192','2035-10-01')),11200::bigint,
  'Monthly calculation combines historical and current tariff correctly');
update public.special_room_rates set hourly_rate_huf=6300
where room_id='11000000-0000-0000-0000-000000000001' and use_type='group'
and date '2035-10-01' between valid_from and coalesce(valid_to,'infinity'::date);
select is((select calculated_due_huf from public.calculate_monthly_pricing('00000000-0000-0000-0000-000000000192','2035-10-01')),11300::bigint,
  'Changed tariff affects new booking while historical rate stays fixed');
select ok(exists(select 1 from pg_proc p cross join parity_function_before b
where p.oid='public.resolve_booking_applied_rate(uuid,integer)'::regprocedure
and md5(p.prosrc)=b.hash and p.proacl::text is not distinct from b.acl),
  'Resolver body and ACL remain unchanged');
select * from finish();
rollback;
