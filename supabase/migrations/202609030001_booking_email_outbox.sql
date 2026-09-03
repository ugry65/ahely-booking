begin;

create table public.booking_email_outbox (
  id uuid primary key default extensions.gen_random_uuid(),
  correlation_id uuid not null,
  deduplication_key text not null unique,
  event_type text not null,
  scope text not null,
  booking_id uuid references public.bookings(id) on delete restrict,
  series_id uuid references public.booking_series(id) on delete restrict,
  recipient_user_id uuid not null references public.profiles(id) on delete restrict,
  recipient_email text not null,
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  performed_by_admin boolean not null,
  payload_version integer not null default 1,
  payload jsonb not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  leased_at timestamptz,
  lease_expires_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  last_error_code text,
  last_error_safe text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint booking_email_outbox_deduplication_key_valid check (
    deduplication_key = correlation_id::text || ':' || event_type || ':' || recipient_user_id::text
    and length(deduplication_key) <= 255
  ),
  constraint booking_email_outbox_event_type_valid check (
    event_type in ('booking.created', 'booking.updated', 'booking.cancelled')
  ),
  constraint booking_email_outbox_scope_valid check (
    scope in ('single', 'occurrence', 'following', 'series')
  ),
  constraint booking_email_outbox_source_valid check (
    (scope = 'single' and booking_id is not null)
    or (scope = 'occurrence' and booking_id is not null and series_id is not null)
    or (scope in ('following', 'series') and series_id is not null)
  ),
  constraint booking_email_outbox_email_valid check (
    recipient_email = lower(trim(recipient_email))
    and length(recipient_email) between 3 and 320
    and position('@' in recipient_email) > 1
  ),
  constraint booking_email_outbox_payload_valid check (
    payload_version > 0 and jsonb_typeof(payload) = 'object'
  ),
  constraint booking_email_outbox_status_valid check (
    status in ('pending', 'sending', 'retry', 'sent', 'dead_letter', 'suppressed', 'captured')
  ),
  constraint booking_email_outbox_attempts_valid check (
    attempts between 0 and 8
    and (status not in ('pending') or attempts = 0)
    and (status not in ('retry', 'sent', 'dead_letter', 'captured') or attempts >= 1)
    and (status <> 'retry' or attempts < 8)
  ),
  constraint booking_email_outbox_lease_valid check (
    (
      status = 'sending'
      and lease_token is not null
      and leased_at is not null
      and lease_expires_at is not null
      and lease_expires_at > leased_at
    )
    or (
      status <> 'sending'
      and lease_token is null
      and leased_at is null
      and lease_expires_at is null
    )
  ),
  constraint booking_email_outbox_sent_valid check (
    (status = 'sent' and sent_at is not null)
    or (status <> 'sent' and sent_at is null)
  ),
  constraint booking_email_outbox_provider_state_valid check (
    (status = 'sent' and provider_message_id is not null)
    or (status <> 'sent' and provider_message_id is null)
  ),
  constraint booking_email_outbox_error_state_valid check (
    (status in ('retry', 'dead_letter') and (last_error_code is not null or last_error_safe is not null))
    or (status not in ('retry', 'dead_letter') and last_error_code is null and last_error_safe is null)
  ),
  constraint booking_email_outbox_provider_message_id_length check (
    provider_message_id is null or length(provider_message_id) <= 500
  ),
  constraint booking_email_outbox_error_length check (
    (last_error_code is null or length(last_error_code) <= 100)
    and (last_error_safe is null or length(last_error_safe) <= 1000)
  )
);

create index booking_email_outbox_due_idx
  on public.booking_email_outbox(next_attempt_at, created_at)
  where status in ('pending', 'retry');

create index booking_email_outbox_expired_lease_idx
  on public.booking_email_outbox(lease_expires_at)
  where status = 'sending';

create index booking_email_outbox_recipient_idx
  on public.booking_email_outbox(recipient_user_id, created_at desc);

create index booking_email_outbox_correlation_idx
  on public.booking_email_outbox(correlation_id);

create index booking_email_outbox_actor_idx
  on public.booking_email_outbox(actor_user_id);

create index booking_email_outbox_booking_idx
  on public.booking_email_outbox(booking_id)
  where booking_id is not null;

create index booking_email_outbox_series_idx
  on public.booking_email_outbox(series_id)
  where series_id is not null;

create table public.booking_email_delivery_attempts (
  id bigint generated always as identity primary key,
  outbox_id uuid not null references public.booking_email_outbox(id) on delete restrict,
  lease_token uuid not null,
  attempt_number integer not null check (attempt_number between 1 and 8),
  outcome text not null check (outcome in ('sent', 'captured', 'retry', 'dead_letter')),
  provider_message_id text,
  error_code text,
  error_safe text,
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  attempted_at timestamptz not null default now(),
  constraint booking_email_delivery_attempt_unique unique (outbox_id, lease_token),
  constraint booking_email_delivery_attempt_provider_length check (
    provider_message_id is null or length(provider_message_id) <= 500
  ),
  constraint booking_email_delivery_attempt_error_length check (
    (error_code is null or length(error_code) <= 100)
    and (error_safe is null or length(error_safe) <= 1000)
  ),
  constraint booking_email_delivery_attempt_result_valid check (
    (
      outcome = 'sent'
      and provider_message_id is not null
      and error_code is null
      and error_safe is null
    )
    or (
      outcome = 'captured'
      and provider_message_id is null
      and error_code is null
      and error_safe is null
    )
    or (
      outcome in ('retry', 'dead_letter')
      and provider_message_id is null
      and (error_code is not null or error_safe is not null)
    )
  )
);

create index booking_email_delivery_attempts_outbox_idx
  on public.booking_email_delivery_attempts(outbox_id, attempt_number);

alter table public.booking_email_outbox enable row level security;
alter table public.booking_email_delivery_attempts enable row level security;

revoke all on table public.booking_email_outbox from public, anon, authenticated, service_role;
revoke all on table public.booking_email_delivery_attempts from public, anon, authenticated, service_role;
revoke all on sequence public.booking_email_delivery_attempts_id_seq from public, anon, authenticated, service_role;

create or replace function public.protect_booking_email_outbox()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'booking_email_outbox is append-only' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
    or new.deduplication_key is distinct from old.deduplication_key
    or new.correlation_id is distinct from old.correlation_id
    or new.event_type is distinct from old.event_type
    or new.scope is distinct from old.scope
    or new.booking_id is distinct from old.booking_id
    or new.series_id is distinct from old.series_id
    or new.recipient_user_id is distinct from old.recipient_user_id
    or new.recipient_email is distinct from old.recipient_email
    or new.actor_user_id is distinct from old.actor_user_id
    or new.performed_by_admin is distinct from old.performed_by_admin
    or new.payload_version is distinct from old.payload_version
    or new.payload is distinct from old.payload
    or new.created_at is distinct from old.created_at
  then
    raise exception 'booking_email_outbox business data is immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger booking_email_outbox_protected
before update or delete on public.booking_email_outbox
for each row execute function public.protect_booking_email_outbox();

create or replace function public.protect_booking_email_delivery_attempts()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'booking_email_delivery_attempts is append-only' using errcode = '42501';
end;
$$;

create trigger booking_email_delivery_attempts_immutable
before update or delete on public.booking_email_delivery_attempts
for each row execute function public.protect_booking_email_delivery_attempts();

create or replace function public.enqueue_booking_email(
  p_correlation_id uuid,
  p_event_type text,
  p_scope text,
  p_booking_id uuid,
  p_series_id uuid,
  p_recipient_user_id uuid,
  p_recipient_email text,
  p_actor_user_id uuid,
  p_performed_by_admin boolean,
  p_payload_version integer,
  p_payload jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_existing public.booking_email_outbox%rowtype;
  v_deduplication_key text := p_correlation_id::text || ':' || p_event_type || ':' || p_recipient_user_id::text;
  v_recipient_email text := lower(trim(p_recipient_email));
begin
  insert into public.booking_email_outbox (
    correlation_id,
    deduplication_key,
    event_type,
    scope,
    booking_id,
    series_id,
    recipient_user_id,
    recipient_email,
    actor_user_id,
    performed_by_admin,
    payload_version,
    payload
  ) values (
    p_correlation_id,
    v_deduplication_key,
    p_event_type,
    p_scope,
    p_booking_id,
    p_series_id,
    p_recipient_user_id,
    v_recipient_email,
    p_actor_user_id,
    p_performed_by_admin,
    p_payload_version,
    p_payload
  )
  on conflict (deduplication_key) do nothing
  returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  select * into v_existing
  from public.booking_email_outbox
  where deduplication_key = v_deduplication_key;

  if not found
    or v_existing.correlation_id is distinct from p_correlation_id
    or v_existing.event_type is distinct from p_event_type
    or v_existing.scope is distinct from p_scope
    or v_existing.booking_id is distinct from p_booking_id
    or v_existing.series_id is distinct from p_series_id
    or v_existing.recipient_user_id is distinct from p_recipient_user_id
    or v_existing.recipient_email is distinct from v_recipient_email
    or v_existing.actor_user_id is distinct from p_actor_user_id
    or v_existing.performed_by_admin is distinct from p_performed_by_admin
    or v_existing.payload_version is distinct from p_payload_version
    or v_existing.payload is distinct from p_payload
  then
    raise exception 'Az e-mail deduplikációs kulcs már eltérő értesítéshez tartozik.' using errcode = 'P0001';
  end if;

  return v_existing.id;
end;
$$;

create or replace function public.claim_booking_email_outbox(
  p_batch_size integer default 20,
  p_lease_seconds integer default 300
)
returns table (
  id uuid,
  lease_token uuid,
  event_type text,
  scope text,
  recipient_email text,
  payload_version integer,
  payload jsonb,
  attempts integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_batch_size is null or p_batch_size not between 1 and 100 then
    raise exception 'A batch mérete 1 és 100 közötti lehet.' using errcode = '22023';
  end if;

  if p_lease_seconds is null or p_lease_seconds not between 30 and 900 then
    raise exception 'A lease időtartama 30 és 900 másodperc közötti lehet.' using errcode = '22023';
  end if;

  return query
  with candidates as (
    select email.id
    from public.booking_email_outbox email
    where email.attempts < 8
      and (
        (email.status in ('pending', 'retry') and email.next_attempt_at <= clock_timestamp())
        or (email.status = 'sending' and email.lease_expires_at <= clock_timestamp())
      )
    order by
      case when email.status = 'sending' then email.lease_expires_at else email.next_attempt_at end,
      email.created_at,
      email.id
    for update skip locked
    limit p_batch_size
  ), claimed as (
    update public.booking_email_outbox email
    set status = 'sending',
        lease_token = extensions.gen_random_uuid(),
        leased_at = clock_timestamp(),
        lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
        updated_at = clock_timestamp()
    from candidates
    where email.id = candidates.id
    returning email.*
  )
  select
    claimed.id,
    claimed.lease_token,
    claimed.event_type,
    claimed.scope,
    claimed.recipient_email,
    claimed.payload_version,
    claimed.payload,
    claimed.attempts
  from claimed
  order by claimed.created_at, claimed.id;
end;
$$;

create or replace function public.complete_booking_email_outbox(
  p_outbox_id uuid,
  p_lease_token uuid,
  p_result text,
  p_provider_message_id text default null,
  p_error_code text default null,
  p_error_safe text default null,
  p_duration_ms integer default null,
  p_next_attempt_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email public.booking_email_outbox%rowtype;
  v_attempt_number integer;
  v_now timestamptz := clock_timestamp();
  v_provider_message_id text := nullif(trim(p_provider_message_id), '');
  v_error_code text := nullif(trim(p_error_code), '');
  v_error_safe text := nullif(trim(p_error_safe), '');
begin
  if p_outbox_id is null or p_lease_token is null then
    raise exception 'Az outbox- és lease-azonosító kötelező.' using errcode = '22023';
  end if;

  if p_result is null or p_result not in ('sent', 'captured', 'retry', 'dead_letter') then
    raise exception 'Ismeretlen e-mail kézbesítési eredmény.' using errcode = '22023';
  end if;

  if p_duration_ms is not null and p_duration_ms < 0 then
    raise exception 'A kézbesítési idő nem lehet negatív.' using errcode = '22023';
  end if;

  if (p_result in ('sent', 'captured') and (v_error_code is not null or v_error_safe is not null))
    or (p_result in ('retry', 'dead_letter') and v_error_code is null and v_error_safe is null)
  then
    raise exception 'A kézbesítési eredmény és a hibamezők nem konzisztensek.' using errcode = '22023';
  end if;

  if (p_result = 'sent' and v_provider_message_id is null)
    or (p_result <> 'sent' and v_provider_message_id is not null)
  then
    raise exception 'Provider Message-ID kizárólag sikeres küldéshez kötelező.' using errcode = '22023';
  end if;

  if p_result = 'retry' and (p_next_attempt_at is null or p_next_attempt_at <= v_now) then
    raise exception 'Retry esetén jövőbeli következő próbálkozási idő kötelező.' using errcode = '22023';
  end if;

  if p_result <> 'retry' and p_next_attempt_at is not null then
    raise exception 'Következő próbálkozási idő csak retry eredménynél adható meg.' using errcode = '22023';
  end if;

  select * into v_email
  from public.booking_email_outbox
  where id = p_outbox_id
    and status = 'sending'
    and lease_token = p_lease_token
  for update;

  if not found then
    raise exception 'Az e-mail lease már nem érvényes.' using errcode = '42501';
  end if;

  v_attempt_number := v_email.attempts + 1;

  if v_attempt_number > 8 then
    raise exception 'Az e-mail elérte a maximális próbálkozásszámot.' using errcode = '22023';
  end if;

  if p_result = 'retry' and v_attempt_number >= 8 then
    raise exception 'A nyolcadik próbálkozás után retry nem rögzíthető.' using errcode = '22023';
  end if;

  insert into public.booking_email_delivery_attempts (
    outbox_id,
    lease_token,
    attempt_number,
    outcome,
    provider_message_id,
    error_code,
    error_safe,
    duration_ms,
    attempted_at
  ) values (
    v_email.id,
    p_lease_token,
    v_attempt_number,
    p_result,
    v_provider_message_id,
    v_error_code,
    v_error_safe,
    p_duration_ms,
    v_now
  );

  update public.booking_email_outbox
  set status = p_result,
      attempts = v_attempt_number,
      next_attempt_at = case when p_result = 'retry' then p_next_attempt_at else next_attempt_at end,
      lease_token = null,
      leased_at = null,
      lease_expires_at = null,
      sent_at = case when p_result = 'sent' then v_now else null end,
      provider_message_id = case when p_result = 'sent' then v_provider_message_id else null end,
      last_error_code = case when p_result in ('retry', 'dead_letter') then v_error_code else null end,
      last_error_safe = case when p_result in ('retry', 'dead_letter') then v_error_safe else null end,
      updated_at = v_now
  where id = v_email.id;
end;
$$;

revoke all on function public.protect_booking_email_outbox() from public, anon, authenticated, service_role;
revoke all on function public.protect_booking_email_delivery_attempts() from public, anon, authenticated, service_role;
revoke all on function public.enqueue_booking_email(uuid,text,text,uuid,uuid,uuid,text,uuid,boolean,integer,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.claim_booking_email_outbox(integer,integer)
  from public, anon, authenticated;
revoke all on function public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz)
  from public, anon, authenticated;

grant execute on function public.claim_booking_email_outbox(integer,integer) to service_role;
grant execute on function public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz) to service_role;

comment on table public.booking_email_outbox is
  'Immutable booking e-mail snapshot plus worker delivery state. Direct client and service-role table access is denied.';
comment on table public.booking_email_delivery_attempts is
  'Append-only safe delivery-attempt audit; no SMTP secrets, MIME bodies or raw provider responses.';
comment on function public.enqueue_booking_email(uuid,text,text,uuid,uuid,uuid,text,uuid,boolean,integer,jsonb) is
  'Internal idempotent enqueue helper for canonical booking RPCs. Direct API execution is intentionally revoked.';
comment on function public.claim_booking_email_outbox(integer,integer) is
  'Service-role-only atomic batch claim using FOR UPDATE SKIP LOCKED and expiring leases.';
comment on function public.complete_booking_email_outbox(uuid,uuid,text,text,text,text,integer,timestamptz) is
  'Service-role-only lease-fenced delivery result and append-only attempt recording.';

commit;
