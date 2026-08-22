begin;

-- The title request ledger is internal-only. It must participate in the public-table
-- RLS invariant even though all writes go through SECURITY DEFINER functions.
alter table public.booking_title_requests enable row level security;
revoke all on table public.booking_title_requests from public, anon, authenticated;

-- The renamed implementation functions are internal plumbing. Do not expose them
-- directly, otherwise callers could bypass the title-aware RPC contract.
revoke all on function public.create_booking_base(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.update_booking_base(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.update_booking_scope_base(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_booking_series_base(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) from public, anon, authenticated, service_role;

-- Preserve the pre-title RPC signatures for backwards compatibility. Legacy callers
-- get exactly the previous behaviour: a booking with no title.
create or replace function public.create_booking(
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
) returns uuid
language sql
security definer
set search_path = ''
as $$
  select public.create_booking(
    p_room_id, p_user_id, p_start_at, p_end_at,
    p_use_type, p_note, p_idempotency_key, null::text
  );
$$;

create or replace function public.update_booking(
  p_booking_id uuid,
  p_expected_updated_at timestamptz,
  p_room_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
) returns uuid
language sql
security definer
set search_path = ''
as $$
  select public.update_booking(
    p_booking_id, p_expected_updated_at, p_room_id, p_start_at, p_end_at,
    p_use_type, p_note, p_idempotency_key, null::text
  );
$$;

create or replace function public.update_booking_scope(
  p_booking_id uuid,
  p_scope text,
  p_expected_updated_at timestamptz,
  p_room_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
) returns integer
language sql
security definer
set search_path = ''
as $$
  select public.update_booking_scope(
    p_booking_id, p_scope, p_expected_updated_at, p_room_id,
    p_start_at, p_end_at, p_use_type, p_note, p_idempotency_key, null::text
  );
$$;

create or replace function public.create_booking_series(
  p_room_id uuid,
  p_user_id uuid,
  p_first_start_at timestamptz,
  p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency,
  p_ends_on date,
  p_occurrence_count integer,
  p_exception_dates date[],
  p_conflict_policy public.conflict_policy,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
) returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.create_booking_series(
    p_room_id, p_user_id, p_first_start_at, p_first_end_at,
    p_frequency, p_ends_on, p_occurrence_count, p_exception_dates,
    p_conflict_policy, p_use_type, p_note, p_idempotency_key, null::text
  );
$$;

-- Keep read-model source explicit and stable; this also preserves the original
-- behavioural contract used by regression tests while adding booking_title.
create or replace function public.list_my_bookings()
returns table(
  booking_id uuid,
  room_id uuid,
  room_name text,
  start_at timestamptz,
  end_at timestamptz,
  use_type public.booking_use_type,
  note text,
  booking_title text,
  series_id uuid,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
begin
  select * into v_actor
  from public.profiles
  where id = auth.uid() and is_active;

  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  return query
  select booking.id, room.id, room.name, booking.start_at, booking.end_at,
    booking.use_type, booking.note, booking.booking_title, booking.series_id, booking.updated_at
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id
  where booking.user_id = v_actor.id
    and booking.status = 'active'
    and booking.start_at > now()
  order by booking.start_at, room.display_order, booking.id;
end;
$$;

create or replace function public.list_calendar_bookings(
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table(
  booking_id uuid,
  room_id uuid,
  room_name text,
  start_at timestamptz,
  end_at timestamptz,
  use_type public.booking_use_type,
  is_own boolean,
  booker_display_name text,
  booking_title text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_show_names boolean := true;
begin
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode = '22023';
  end if;
  if p_end_at - p_start_at > interval '62 days' then
    raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode = '22023';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid() and is_active;
  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  select coalesce((value #>> '{}')::boolean, true)
  into v_show_names
  from public.app_settings
  where key = 'show_other_booker_names';

  return query
  select b.id, r.id, r.name, b.start_at, b.end_at, b.use_type,
    b.user_id = v_actor.id,
    case
      when v_actor.role = 'admin' or b.user_id = v_actor.id or v_show_names
        then nullif(btrim(p.last_name || ' ' || p.first_name), '')
      else null
    end,
    case
      when v_actor.role = 'admin' or b.user_id = v_actor.id then b.booking_title
      else null
    end
  from public.bookings b
  join public.rooms r on r.id = b.room_id and r.is_active
  join public.profiles p on p.id = b.user_id
  where b.status = 'active'
    and b.start_at < p_end_at
    and b.end_at > p_start_at
    and (
      v_actor.role = 'admin'
      or exists (
        select 1
        from public.effective_room_permissions(v_actor.id) permission
        where permission.room_id = r.id and permission.can_book
      )
    )
  order by b.start_at, r.display_order, b.id;
end;
$$;

-- Functions are executable by PUBLIC unless explicitly revoked.
revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.list_my_bookings() from public, anon;
revoke all on function public.list_calendar_bookings(timestamptz,timestamptz) from public, anon;
revoke all on function public.list_calendar_booking_management(timestamptz,timestamptz) from public, anon;
revoke all on function public.claim_booking_title_request(uuid,text,text) from public, anon;

-- Both legacy and title-aware signatures remain authenticated APIs.
grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.list_my_bookings() to authenticated, service_role;
grant execute on function public.list_calendar_bookings(timestamptz,timestamptz) to authenticated, service_role;
grant execute on function public.list_calendar_booking_management(timestamptz,timestamptz) to authenticated, service_role;
grant execute on function public.claim_booking_title_request(uuid,text,text) to authenticated, service_role;

commit;
