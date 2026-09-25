begin;

select plan(11);

-- Regression coverage for the compatibility migration that retires the
-- historical Training-room booking-rate column only when it carries no data.
-- The pristine 0->HEAD schema has already retired the column, so this test
-- recreates the exact legacy surface and exercises both data-dependent paths
-- inside a transaction that is rolled back at the end.

alter table public.bookings
  add column group_hourly_rate_huf bigint
  check (group_hourly_rate_huf is null or group_hourly_rate_huf >= 0);

create or replace function public.apply_training_group_booking_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return new;
end;
$$;

create trigger bookings_training_group_rate_default
before insert or update of room_id, use_type, group_hourly_rate_huf on public.bookings
for each row execute function public.apply_training_group_booking_rate();

create or replace function public.admin_set_booking_group_rate(
  p_booking_id uuid,
  p_hourly_rate_huf bigint,
  p_correlation_id uuid
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select p_hourly_rate_huf;
$$;

-- Branch A: an empty legacy column is safe to retire.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bookings'
      and column_name = 'group_hourly_rate_huf'
  ) and not exists (
    select 1 from public.bookings
    where group_hourly_rate_huf is not null
  ) then
    drop trigger if exists bookings_training_group_rate_default on public.bookings;
    drop function if exists public.admin_set_booking_group_rate(uuid,bigint,uuid);
    drop function if exists public.apply_training_group_booking_rate();
    alter table public.bookings drop column group_hourly_rate_huf;
  end if;
end;
$$;

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='bookings'
      and column_name='group_hourly_rate_huf'
  ),
  'Üres legacy Tréningterem-díj oszlop biztonságosan eltávolítható'
);
select ok(
  not exists (
    select 1 from pg_trigger
    where tgrelid='public.bookings'::regclass
      and tgname='bookings_training_group_rate_default'
      and not tgisinternal
  ),
  'Üres legacy ág eltávolítja a legacy triggert'
);
select ok(
  to_regprocedure('public.admin_set_booking_group_rate(uuid,bigint,uuid)') is null,
  'Üres legacy ág eltávolítja a legacy admin függvényt'
);
select ok(
  to_regprocedure('public.apply_training_group_booking_rate()') is null,
  'Üres legacy ág eltávolítja a legacy triggerfüggvényt'
);

-- Branch B: any historical value must fail closed and preserve the complete
-- compatibility surface.
alter table public.bookings
  add column group_hourly_rate_huf bigint
  check (group_hourly_rate_huf is null or group_hourly_rate_huf >= 0);

create or replace function public.apply_training_group_booking_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  return new;
end;
$$;

create trigger bookings_training_group_rate_default
before insert or update of room_id, use_type, group_hourly_rate_huf on public.bookings
for each row execute function public.apply_training_group_booking_rate();

create or replace function public.admin_set_booking_group_rate(
  p_booking_id uuid,
  p_hourly_rate_huf bigint,
  p_correlation_id uuid
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select p_hourly_rate_huf;
$$;

insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000191','legacy-training@example.invalid',
  '{"first_name":"Legacy","last_name":"Training"}');

insert into public.bookings(
  id,room_id,user_id,created_by,start_at,end_at,use_type,status,idempotency_key,
  group_hourly_rate_huf
) values (
  '41000000-0000-0000-0000-000000000191',
  '11000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000191',
  '00000000-0000-0000-0000-000000000191',
  '2026-09-15 07:00+02','2026-09-15 08:00+02','group','active',
  gen_random_uuid(),7500
);

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bookings'
      and column_name = 'group_hourly_rate_huf'
  ) and not exists (
    select 1 from public.bookings
    where group_hourly_rate_huf is not null
  ) then
    drop trigger if exists bookings_training_group_rate_default on public.bookings;
    drop function if exists public.admin_set_booking_group_rate(uuid,bigint,uuid);
    drop function if exists public.apply_training_group_booking_rate();
    alter table public.bookings drop column group_hourly_rate_huf;
  end if;
end;
$$;

select has_column(
  'public','bookings','group_hourly_rate_huf',
  'Történeti érték esetén a legacy díjoszlop megmarad'
);
select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid='public.bookings'::regclass
      and tgname='bookings_training_group_rate_default'
      and not tgisinternal
  ),
  'Történeti érték esetén a legacy trigger megmarad'
);
select ok(
  to_regprocedure('public.admin_set_booking_group_rate(uuid,bigint,uuid)') is not null,
  'Történeti érték esetén a legacy admin függvény megmarad'
);
select ok(
  to_regprocedure('public.apply_training_group_booking_rate()') is not null,
  'Történeti érték esetén a legacy triggerfüggvény megmarad'
);

-- The historical booking value must beat the newer special-room tariff, while
-- an explicit booking override remains the highest-precedence rule.
select is(
  (select rate_source::text||':'||hourly_rate_huf
   from public.resolve_booking_applied_rate(
     '41000000-0000-0000-0000-000000000191',0
   )),
  'training_room:7500',
  'A resolver a történeti Tréningterem-díjat őrzi meg az új teremtarifa helyett'
);

update public.bookings
set hourly_rate_override_huf=8100,
    hourly_rate_override_set_by='00000000-0000-0000-0000-000000000191',
    hourly_rate_override_set_at=now(),
    hourly_rate_override_reason='Legacy precedence regressziós teszt'
where id='41000000-0000-0000-0000-000000000191';

select is(
  (select rate_source::text||':'||hourly_rate_huf
   from public.resolve_booking_applied_rate(
     '41000000-0000-0000-0000-000000000191',0
   )),
  'booking_override:8100',
  'A booking override továbbra is megelőzi a legacy Tréningterem-díjat'
);

select is(
  (select calculated_due_huf
   from public.calculate_monthly_pricing(
     '00000000-0000-0000-0000-000000000191','2026-09-01'
   )),
  8100::bigint,
  'A havi pricing ugyanazt a precedence láncot használja'
);

select * from finish();
rollback;
