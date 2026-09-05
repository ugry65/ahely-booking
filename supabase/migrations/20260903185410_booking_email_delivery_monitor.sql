begin;

create table public.booking_email_worker_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  mode text not null,
  status text not null default 'running',
  claimed_count integer not null default 0,
  sent_count integer not null default 0,
  captured_count integer not null default 0,
  retry_count integer not null default 0,
  dead_letter_count integer not null default 0,
  error_code text,
  error_safe text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint booking_email_worker_runs_mode_valid check (mode in ('capture', 'send')),
  constraint booking_email_worker_runs_status_valid check (status in ('running', 'success', 'failed')),
  constraint booking_email_worker_runs_counts_valid check (
    claimed_count >= 0
    and sent_count >= 0
    and captured_count >= 0
    and retry_count >= 0
    and dead_letter_count >= 0
    and claimed_count >= sent_count + captured_count + retry_count + dead_letter_count
  ),
  constraint booking_email_worker_runs_state_valid check (
    (
      status = 'running'
      and finished_at is null
      and claimed_count = 0
      and sent_count = 0
      and captured_count = 0
      and retry_count = 0
      and dead_letter_count = 0
      and error_code is null
      and error_safe is null
    )
    or (
      status = 'success'
      and finished_at is not null
      and finished_at >= started_at
      and claimed_count = sent_count + captured_count + retry_count + dead_letter_count
      and error_code is null
      and error_safe is null
    )
    or (
      status = 'failed'
      and finished_at is not null
      and finished_at >= started_at
      and error_code is not null
      and error_safe is not null
    )
  ),
  constraint booking_email_worker_runs_error_length check (
    (error_code is null or length(error_code) <= 100)
    and (error_safe is null or length(error_safe) <= 500)
  )
);

create index booking_email_worker_runs_started_idx
  on public.booking_email_worker_runs(started_at desc);

create index booking_email_worker_runs_success_idx
  on public.booking_email_worker_runs(finished_at desc)
  where status = 'success';

create index booking_email_outbox_monitor_problems_idx
  on public.booking_email_outbox(updated_at desc)
  where status in ('retry', 'dead_letter', 'sending');

create index booking_email_delivery_attempts_smtp_auth_idx
  on public.booking_email_delivery_attempts(attempted_at desc)
  where error_code = 'smtp_auth';

alter table public.booking_email_worker_runs enable row level security;

revoke all on table public.booking_email_worker_runs from public, anon, authenticated, service_role;

create or replace function public.protect_booking_email_worker_runs()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'booking_email_worker_runs is append-only' using errcode = '42501';
  end if;

  if new.id is distinct from old.id
    or new.mode is distinct from old.mode
    or new.started_at is distinct from old.started_at
  then
    raise exception 'booking_email_worker_runs identity is immutable' using errcode = '42501';
  end if;

  if old.status <> 'running' or new.status = 'running' then
    raise exception 'booking_email_worker_runs can only be completed once' using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger booking_email_worker_runs_protected
before update or delete on public.booking_email_worker_runs
for each row execute function public.protect_booking_email_worker_runs();

create or replace function public.start_booking_email_worker_run(p_mode text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id uuid;
begin
  if p_mode is null or p_mode not in ('capture', 'send') then
    raise exception 'A worker mód csak capture vagy send lehet.' using errcode = '22023';
  end if;

  insert into public.booking_email_worker_runs (mode)
  values (p_mode)
  returning id into v_run_id;

  return v_run_id;
end;
$$;

create or replace function public.finish_booking_email_worker_run(
  p_run_id uuid,
  p_outcome text,
  p_claimed_count integer default 0,
  p_sent_count integer default 0,
  p_captured_count integer default 0,
  p_retry_count integer default 0,
  p_dead_letter_count integer default 0,
  p_error_code text default null,
  p_error_safe text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_error_code text := nullif(trim(p_error_code), '');
  v_error_safe text := nullif(trim(p_error_safe), '');
begin
  if p_run_id is null or p_outcome is null or p_outcome not in ('success', 'failed') then
    raise exception 'Érvénytelen worker-futás eredmény.' using errcode = '22023';
  end if;

  if p_claimed_count is null or p_claimed_count < 0
    or p_sent_count is null or p_sent_count < 0
    or p_captured_count is null or p_captured_count < 0
    or p_retry_count is null or p_retry_count < 0
    or p_dead_letter_count is null or p_dead_letter_count < 0
    or p_claimed_count < p_sent_count + p_captured_count + p_retry_count + p_dead_letter_count
  then
    raise exception 'Érvénytelen worker-futás darabszámok.' using errcode = '22023';
  end if;

  if (p_outcome = 'success' and (
      p_claimed_count <> p_sent_count + p_captured_count + p_retry_count + p_dead_letter_count
      or v_error_code is not null
      or v_error_safe is not null
    ))
    or (p_outcome = 'failed' and (v_error_code is null or v_error_safe is null))
  then
    raise exception 'A worker-futás eredménye és hibamezői nem konzisztensek.' using errcode = '22023';
  end if;

  update public.booking_email_worker_runs
  set status = p_outcome,
      claimed_count = p_claimed_count,
      sent_count = p_sent_count,
      captured_count = p_captured_count,
      retry_count = p_retry_count,
      dead_letter_count = p_dead_letter_count,
      error_code = case when p_outcome = 'failed' then v_error_code else null end,
      error_safe = case when p_outcome = 'failed' then v_error_safe else null end,
      finished_at = clock_timestamp()
  where id = p_run_id
    and status = 'running';

  if not found then
    raise exception 'A worker-futás nem található vagy már lezárt.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_booking_email_monitor()
returns table (
  pending_count bigint,
  retry_count bigint,
  sending_count bigint,
  dead_letter_count bigint,
  captured_count bigint,
  suppressed_count bigint,
  sent_count bigint,
  sent_24h_count bigint,
  due_count bigint,
  stale_sending_count bigint,
  stale_worker_run_count bigint,
  smtp_auth_error_24h_count bigint,
  oldest_due_at timestamptz,
  last_sent_at timestamptz,
  last_worker_started_at timestamptz,
  last_worker_success_at timestamptz,
  last_worker_failure_at timestamptz,
  database_now timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();

  return query
  select
    count(*) filter (where email.status = 'pending')::bigint,
    count(*) filter (where email.status = 'retry')::bigint,
    count(*) filter (where email.status = 'sending')::bigint,
    count(*) filter (where email.status = 'dead_letter')::bigint,
    count(*) filter (where email.status = 'captured')::bigint,
    count(*) filter (where email.status = 'suppressed')::bigint,
    count(*) filter (where email.status = 'sent')::bigint,
    count(*) filter (
      where email.status = 'sent'
        and email.sent_at >= statement_timestamp() - interval '24 hours'
    )::bigint,
    count(*) filter (
      where email.status in ('pending', 'retry')
        and email.next_attempt_at <= statement_timestamp()
    )::bigint,
    count(*) filter (
      where email.status = 'sending'
        and email.lease_expires_at <= statement_timestamp()
    )::bigint,
    (
      select count(*)::bigint
      from public.booking_email_worker_runs run
      where run.status = 'running'
        and run.started_at <= statement_timestamp() - interval '30 minutes'
    ),
    (
      select count(*)::bigint
      from public.booking_email_delivery_attempts attempt
      where attempt.error_code = 'smtp_auth'
        and attempt.attempted_at >= statement_timestamp() - interval '24 hours'
    ),
    min(email.next_attempt_at) filter (
      where email.status in ('pending', 'retry')
        and email.next_attempt_at <= statement_timestamp()
    ),
    max(email.sent_at) filter (where email.status = 'sent'),
    (select max(run.started_at) from public.booking_email_worker_runs run),
    (
      select max(run.finished_at)
      from public.booking_email_worker_runs run
      where run.status = 'success'
    ),
    (
      select max(run.finished_at)
      from public.booking_email_worker_runs run
      where run.status = 'failed'
    ),
    statement_timestamp()
  from public.booking_email_outbox email;
end;
$$;

create or replace function public.admin_booking_email_problem_items(p_limit integer default 50)
returns table (
  outbox_id uuid,
  problem_kind text,
  event_type text,
  scope text,
  status text,
  attempts integer,
  next_attempt_at timestamptz,
  lease_expires_at timestamptz,
  last_error_code text,
  last_error_safe text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();

  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'A monitor lista mérete 1 és 100 közötti lehet.' using errcode = '22023';
  end if;

  return query
  select
    email.id,
    case
      when email.status = 'dead_letter' then 'dead_letter'
      when email.status = 'sending' then 'stale_sending'
      else 'retry'
    end,
    email.event_type,
    email.scope,
    email.status,
    email.attempts,
    email.next_attempt_at,
    email.lease_expires_at,
    email.last_error_code,
    email.last_error_safe,
    email.created_at,
    email.updated_at
  from public.booking_email_outbox email
  where email.status in ('retry', 'dead_letter')
    or (email.status = 'sending' and email.lease_expires_at <= statement_timestamp())
  order by
    case email.status when 'dead_letter' then 0 when 'sending' then 1 else 2 end,
    email.updated_at desc,
    email.id
  limit p_limit;
end;
$$;

create or replace function public.admin_booking_email_worker_runs(p_limit integer default 20)
returns table (
  run_id uuid,
  mode text,
  status text,
  claimed_count integer,
  sent_count integer,
  captured_count integer,
  retry_count integer,
  dead_letter_count integer,
  error_code text,
  error_safe text,
  started_at timestamptz,
  finished_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();

  if p_limit is null or p_limit not between 1 and 100 then
    raise exception 'A worker-futás lista mérete 1 és 100 közötti lehet.' using errcode = '22023';
  end if;

  return query
  select
    run.id,
    run.mode,
    run.status,
    run.claimed_count,
    run.sent_count,
    run.captured_count,
    run.retry_count,
    run.dead_letter_count,
    run.error_code,
    run.error_safe,
    run.started_at,
    run.finished_at
  from public.booking_email_worker_runs run
  order by run.started_at desc, run.id
  limit p_limit;
end;
$$;

revoke all on function public.protect_booking_email_worker_runs()
  from public, anon, authenticated, service_role;
revoke all on function public.start_booking_email_worker_run(text)
  from public, anon, authenticated;
revoke all on function public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text)
  from public, anon, authenticated;
revoke all on function public.admin_booking_email_monitor()
  from public, anon;
revoke all on function public.admin_booking_email_problem_items(integer)
  from public, anon;
revoke all on function public.admin_booking_email_worker_runs(integer)
  from public, anon;

grant execute on function public.start_booking_email_worker_run(text) to service_role;
grant execute on function public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text)
  to service_role;
grant execute on function public.admin_booking_email_monitor() to authenticated;
grant execute on function public.admin_booking_email_problem_items(integer) to authenticated;
grant execute on function public.admin_booking_email_worker_runs(integer) to authenticated;

comment on table public.booking_email_worker_runs is
  'Auditált worker heartbeat és összesített futáseredmény. Nem tartalmaz címzettet, levéltörzset, provider választ vagy titkot.';
comment on function public.start_booking_email_worker_run(text) is
  'Service-role-only worker futás indítása; a disabled mód szándékosan nem ír heartbeatot.';
comment on function public.finish_booking_email_worker_run(uuid,text,integer,integer,integer,integer,integer,text,text) is
  'Service-role-only egyszer lezárható worker futás biztonságos összesítővel.';
comment on function public.admin_booking_email_monitor() is
  'Admin-only minimális e-mail kézbesítési read model címzett és payload nélkül.';
comment on function public.admin_booking_email_problem_items(integer) is
  'Admin-only problémalista címzett, booking payload és provider részletek nélkül.';
comment on function public.admin_booking_email_worker_runs(integer) is
  'Admin-only worker heartbeat előzmény kizárólag biztonságos összesítő adatokkal.';

commit;
