begin;

-- Legacy RPCs must preserve the exact pre-title behaviour. They delegate directly
-- to the original internal implementations and therefore do not create title ledger
-- rows or title-specific audit records.
create or replace function public.create_booking(
  p_room_id uuid, p_user_id uuid, p_start_at timestamptz, p_end_at timestamptz,
  p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid
) returns uuid language sql security definer set search_path='' as $$
  select public.create_booking_base(
    p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key
  );
$$;

create or replace function public.update_booking(
  p_booking_id uuid, p_expected_updated_at timestamptz, p_room_id uuid, p_start_at timestamptz,
  p_end_at timestamptz, p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid
) returns uuid language sql security definer set search_path='' as $$
  select public.update_booking_base(
    p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,
    p_use_type,p_note,p_idempotency_key
  );
$$;

create or replace function public.update_booking_scope(
  p_booking_id uuid, p_scope text, p_expected_updated_at timestamptz, p_room_id uuid,
  p_start_at timestamptz, p_end_at timestamptz, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid
) returns integer language sql security definer set search_path='' as $$
  select public.update_booking_scope_base(
    p_booking_id,p_scope,p_expected_updated_at,p_room_id,p_start_at,p_end_at,
    p_use_type,p_note,p_idempotency_key
  );
$$;

create or replace function public.create_booking_series(
  p_room_id uuid, p_user_id uuid, p_first_start_at timestamptz, p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency, p_ends_on date, p_occurrence_count integer,
  p_exception_dates date[], p_conflict_policy public.conflict_policy, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid
) returns jsonb language sql security definer set search_path='' as $$
  select public.create_booking_series_base(
    p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,
    p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key
  );
$$;

-- Title-aware series creation adds a title-specific audit event only when a title
-- actually exists. A title-less call must not create an extra audit side effect.
create or replace function public.create_booking_series(
  p_room_id uuid, p_user_id uuid, p_first_start_at timestamptz, p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency, p_ends_on date, p_occurrence_count integer,
  p_exception_dates date[], p_conflict_policy public.conflict_policy, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid, p_booking_title text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_series_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'series_create',p_booking_title);
  v_result := public.create_booking_series_base(
    p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,
    p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key
  );
  v_series_id := (v_result->>'series_id')::uuid;
  update public.booking_series
  set booking_title=v_title
  where id=v_series_id and booking_title is distinct from v_title;
  update public.bookings
  set booking_title=v_title, updated_at=clock_timestamp()
  where series_id=v_series_id and booking_title is distinct from v_title;
  if v_title is not null then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(
      auth.uid(),'booking_series.title_set','booking_series',v_series_id::text,
      jsonb_build_object('booking_title_changed',true),p_idempotency_key
    );
  end if;
  return v_result;
end;
$$;

revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) from public, anon;

grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) to authenticated, service_role;

commit;
