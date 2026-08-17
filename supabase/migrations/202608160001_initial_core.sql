begin;

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create type public.app_role as enum ('admin', 'user');
create type public.booking_status as enum ('active', 'cancelled');
create type public.booking_use_type as enum ('individual', 'group');
create type public.recurrence_frequency as enum ('daily', 'weekly', 'biweekly', 'monthly');
create type public.conflict_policy as enum ('abort_all', 'create_available');
create type public.pricing_mode as enum ('tiered', 'fixed_user', 'special_room');
create type public.payment_status as enum ('payable', 'partially_paid', 'paid', 'not_payable_adjustment');
create type public.payment_method as enum ('cash', 'bank_transfer');
create type public.money_destination as enum ('private_otp', 'teem_otp', 'cash_register');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  first_name text not null,
  last_name text not null,
  email text not null,
  phone text,
  organization text,
  role public.app_role not null default 'user',
  is_active boolean not null default true,
  dashboard_enabled boolean not null default false,
  other_booker_names_visible boolean not null default true,
  advance_booking_days_override integer check (advance_booking_days_override is null or advance_booking_days_override >= 0),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_email_lowercase check (email = lower(email)),
  constraint profiles_email_unique unique (email)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  display_order integer not null,
  is_training_room boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rooms_display_order_nonnegative check (display_order >= 0)
);

create table public.access_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.access_group_members (
  group_id uuid not null references public.access_groups(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  primary key (group_id, user_id)
);

create table public.user_room_permissions (
  user_id uuid not null references public.profiles(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  can_book boolean not null default true,
  can_repeat boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create table public.access_group_rooms (
  group_id uuid not null references public.access_groups(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  can_book boolean not null default true,
  can_repeat boolean not null default false,
  primary key (group_id, room_id)
);

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  description text not null,
  updated_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create table public.weekly_opening_hours (
  iso_weekday smallint primary key check (iso_weekday between 1 and 7),
  opens_at time,
  closes_at time,
  is_closed boolean not null default false,
  constraint weekly_hours_valid check (
    (is_closed and opens_at is null and closes_at is null)
    or (not is_closed and opens_at is not null and closes_at is not null and closes_at > opens_at)
  )
);

create table public.calendar_exceptions (
  service_date date primary key,
  opens_at time,
  closes_at time,
  is_closed boolean not null default true,
  reason text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint calendar_exception_valid check (
    (is_closed and opens_at is null and closes_at is null)
    or (not is_closed and opens_at is not null and closes_at is not null and closes_at > opens_at)
  )
);

create table public.pricing_tiers (
  id uuid primary key default gen_random_uuid(),
  min_minutes integer not null check (min_minutes >= 0),
  max_minutes integer check (
    max_minutes is null
    or (max_minutes >= min_minutes and max_minutes < 2147483647)
  ),
  minute_range int4range generated always as (
    int4range(min_minutes, case when max_minutes is null then null else max_minutes + 1 end, '[)')
  ) stored,
  hourly_rate_huf bigint not null check (hourly_rate_huf >= 0),
  valid_from date not null,
  valid_to date,
  valid_period daterange generated always as (
    daterange(valid_from, coalesce(valid_to + 1, 'infinity'::date), '[)')
  ) stored,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint pricing_tier_dates_valid check (valid_to is null or valid_to >= valid_from),
  constraint pricing_tier_no_overlap exclude using gist (
    minute_range with &&,
    valid_period with &&
  )
);

create table public.user_price_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  hourly_rate_huf bigint not null check (hourly_rate_huf >= 0),
  valid_from date not null,
  valid_to date,
  valid_period daterange generated always as (
    daterange(valid_from, coalesce(valid_to + 1, 'infinity'::date), '[)')
  ) stored,
  reason text not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint user_price_override_dates_valid check (valid_to is null or valid_to >= valid_from),
  constraint user_price_override_no_overlap exclude using gist (
    user_id with =,
    valid_period with &&
  )
);

create table public.special_room_rates (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete restrict,
  use_type public.booking_use_type not null,
  hourly_rate_huf bigint not null check (hourly_rate_huf >= 0),
  valid_from date not null,
  valid_to date,
  valid_period daterange generated always as (
    daterange(valid_from, coalesce(valid_to + 1, 'infinity'::date), '[)')
  ) stored,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint special_room_rate_dates_valid check (valid_to is null or valid_to >= valid_from),
  constraint special_room_rate_unique unique (room_id, use_type, valid_from),
  constraint special_room_rate_no_overlap exclude using gist (
    room_id with =,
    use_type with =,
    valid_period with &&
  )
);

create table public.booking_series (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  frequency public.recurrence_frequency not null,
  timezone text not null default 'Europe/Budapest',
  starts_on date not null,
  ends_on date,
  occurrence_count integer,
  exception_dates date[] not null default '{}',
  conflict_policy public.conflict_policy not null,
  created_at timestamptz not null default now(),
  constraint booking_series_end_mode check ((ends_on is null) <> (occurrence_count is null)),
  constraint booking_series_count_positive check (occurrence_count is null or occurrence_count > 0),
  constraint booking_series_dates_valid check (ends_on is null or ends_on >= starts_on)
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  series_id uuid references public.booking_series(id) on delete restrict,
  start_at timestamptz not null,
  end_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(start_at, end_at, '[)')) stored,
  use_type public.booking_use_type not null default 'individual',
  status public.booking_status not null default 'active',
  note text,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bookings_end_after_start check (end_at > start_at),
  constraint bookings_minimum_duration check (extract(epoch from (end_at - start_at)) >= 3600),
  constraint bookings_half_hour_duration check ((extract(epoch from (end_at - start_at))::bigint % 1800) = 0),
  constraint bookings_start_grid check ((extract(epoch from start_at)::bigint % 1800) = 0),
  constraint bookings_end_grid check ((extract(epoch from end_at)::bigint % 1800) = 0),
  constraint bookings_same_budapest_day check (
    (start_at at time zone 'Europe/Budapest')::date = (end_at at time zone 'Europe/Budapest')::date
  ),
  constraint bookings_idempotency_unique unique (created_by, idempotency_key),
  constraint bookings_no_room_overlap exclude using gist (
    room_id with =,
    time_range with &&
  ) where (status = 'active')
);

create index bookings_room_start_idx on public.bookings(room_id, start_at);
create index bookings_user_start_idx on public.bookings(user_id, start_at);
create index bookings_series_idx on public.bookings(series_id) where series_id is not null;

create table public.booking_cancellations (
  booking_id uuid primary key references public.bookings(id) on delete restrict,
  cancelled_by uuid not null references public.profiles(id) on delete restrict,
  cancelled_at timestamptz not null default now(),
  minutes_before_start integer not null,
  reason text,
  original_snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table public.monthly_settlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  settlement_month date not null,
  status public.payment_status not null default 'payable',
  invoice_requested boolean not null default false,
  invoice_number text,
  admin_note text,
  updated_at timestamptz not null default now(),
  constraint monthly_settlement_month_start check (settlement_month = date_trunc('month', settlement_month)::date),
  constraint monthly_settlement_unique unique (user_id, settlement_month)
);

create table public.settlement_revisions (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.monthly_settlements(id) on delete restrict,
  revision_number integer not null check (revision_number > 0),
  normal_minutes integer not null default 0 check (normal_minutes >= 0),
  special_minutes integer not null default 0 check (special_minutes >= 0),
  calculated_due_huf bigint not null default 0 check (calculated_due_huf >= 0),
  calculation_input_hash text not null,
  calculated_by uuid references public.profiles(id) on delete restrict,
  calculated_at timestamptz not null default now(),
  constraint settlement_revision_unique unique (settlement_id, revision_number)
);

create table public.settlement_booking_lines (
  id uuid primary key default gen_random_uuid(),
  settlement_revision_id uuid not null references public.settlement_revisions(id) on delete restrict,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  duration_minutes integer not null check (duration_minutes > 0),
  pricing_mode public.pricing_mode not null,
  pricing_rule_id uuid,
  hourly_rate_huf bigint not null check (hourly_rate_huf >= 0),
  amount_huf bigint not null check (amount_huf >= 0),
  created_at timestamptz not null default now(),
  constraint settlement_booking_line_unique unique (settlement_revision_id, booking_id)
);

create table public.settlement_adjustments (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.monthly_settlements(id) on delete restrict,
  amount_huf bigint not null check (amount_huf <> 0),
  reason text not null check (length(trim(reason)) > 0),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.monthly_settlements(id) on delete restrict,
  amount_huf bigint not null check (amount_huf > 0),
  paid_on date not null,
  method public.payment_method not null,
  destination public.money_destination not null,
  admin_note text,
  idempotency_key uuid not null unique,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.export_runs (
  id uuid primary key default gen_random_uuid(),
  settlement_month date not null,
  export_kind text not null,
  snapshot_manifest jsonb not null,
  file_sha256 text not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint export_month_start check (settlement_month = date_trunc('month', settlement_month)::date)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_user_id uuid references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  before_data jsonb,
  after_data jsonb,
  reason text,
  correlation_id uuid not null,
  request_ip inet
);

create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, occurred_at desc);
create index audit_logs_actor_idx on public.audit_logs(actor_user_id, occurred_at desc);

create table public.outbox_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  payload jsonb not null,
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

create index outbox_pending_idx on public.outbox_events(available_at) where processed_at is null;

create table public.system_error_logs (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  severity text not null,
  error_code text not null,
  correlation_id uuid,
  safe_context jsonb not null default '{}',
  resolved_at timestamptz
);

create table public.retention_candidates (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id text not null,
  eligible_on date not null,
  notified_days integer[] not null default '{}',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint retention_candidate_unique unique (entity_type, entity_id)
);

insert into public.app_settings (key, value, description) values
  ('timezone', '"Europe/Budapest"', 'Alkalmazás időzónája'),
  ('currency', '"HUF"', 'Elszámolási pénznem'),
  ('opening_time', '"07:00"', 'Alap nyitás'),
  ('closing_time', '"22:00"', 'Alap zárás'),
  ('slot_minutes', '30', 'Foglalási időegység percben'),
  ('minimum_booking_minutes', '60', 'Minimum foglalási idő percben'),
  ('default_advance_booking_days', '90', 'Normál user alap előrefoglalási limitje'),
  ('training_room_advance_days', '10', 'Tréningterem normál user limitje'),
  ('cancellation_cutoff_hours', '24', 'Normál user lemondási határideje');

insert into public.weekly_opening_hours (iso_weekday, opens_at, closes_at, is_closed)
select day_no, time '07:00', time '22:00', false
from generate_series(1, 7) as day_no;

insert into public.pricing_tiers (min_minutes, max_minutes, hourly_rate_huf, valid_from) values
  (60, 900, 2700, date '2026-01-01'),
  (901, 3600, 1900, date '2026-01-01'),
  (3601, null, 1700, date '2026-01-01');

create or replace function public.prevent_audit_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end;
$$;

create trigger audit_logs_immutable
before update or delete on public.audit_logs
for each row execute function public.prevent_audit_mutation();

create or replace function public.prevent_physical_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'physical delete is forbidden for %', tg_table_name using errcode = '42501';
end;
$$;

create trigger bookings_no_physical_delete
before delete on public.bookings
for each row execute function public.prevent_physical_delete();

create trigger payments_no_physical_delete
before delete on public.payments
for each row execute function public.prevent_physical_delete();

create trigger settlement_booking_lines_no_physical_delete
before delete on public.settlement_booking_lines
for each row execute function public.prevent_physical_delete();

alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.access_groups enable row level security;
alter table public.access_group_members enable row level security;
alter table public.user_room_permissions enable row level security;
alter table public.access_group_rooms enable row level security;
alter table public.app_settings enable row level security;
alter table public.weekly_opening_hours enable row level security;
alter table public.calendar_exceptions enable row level security;
alter table public.pricing_tiers enable row level security;
alter table public.user_price_overrides enable row level security;
alter table public.special_room_rates enable row level security;
alter table public.booking_series enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_cancellations enable row level security;
alter table public.monthly_settlements enable row level security;
alter table public.settlement_revisions enable row level security;
alter table public.settlement_booking_lines enable row level security;
alter table public.settlement_adjustments enable row level security;
alter table public.payments enable row level security;
alter table public.export_runs enable row level security;
alter table public.audit_logs enable row level security;
alter table public.outbox_events enable row level security;
alter table public.system_error_logs enable row level security;
alter table public.retention_candidates enable row level security;

-- RLS is deliberately deny-by-default in this first migration. Explicit read
-- policies and transactional write RPCs arrive in the auth milestone.

commit;
