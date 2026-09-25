begin;

create or replace function public.admin_create_booking_with_group_rate(
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid,
  p_booking_title text,
  p_group_hourly_rate_huf bigint
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_id uuid;
  v_correlation_id uuid := extensions.gen_random_uuid();
begin
  perform public.require_active_admin();
  if p_group_hourly_rate_huf is null or p_group_hourly_rate_huf < 0 then
    raise exception 'A csoportos óradíj csak 0 vagy pozitív egész forint lehet.' using errcode = '22023';
  end if;

  v_booking_id := public.create_booking(
    p_room_id,
    p_user_id,
    p_start_at,
    p_end_at,
    p_use_type,
    p_note,
    p_idempotency_key,
    p_booking_title
  );

  perform public.admin_set_booking_group_rate(
    v_booking_id,
    p_group_hourly_rate_huf,
    v_correlation_id
  );

  return v_booking_id;
end;
$$;

create or replace function public.admin_create_booking_series_with_group_rate(
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
  p_idempotency_key uuid,
  p_booking_title text,
  p_group_hourly_rate_huf bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_series_id uuid;
  v_correlation_id uuid := extensions.gen_random_uuid();
begin
  perform public.require_active_admin();
  if p_group_hourly_rate_huf is null or p_group_hourly_rate_huf < 0 then
    raise exception 'A csoportos óradíj csak 0 vagy pozitív egész forint lehet.' using errcode = '22023';
  end if;

  v_result := public.create_booking_series(
    p_room_id,
    p_user_id,
    p_first_start_at,
    p_first_end_at,
    p_frequency,
    p_ends_on,
    p_occurrence_count,
    p_exception_dates,
    p_conflict_policy,
    p_use_type,
    p_note,
    p_idempotency_key,
    p_booking_title
  );

  v_series_id := nullif(v_result ->> 'series_id', '')::uuid;
  if v_series_id is null then
    raise exception 'A létrehozott sorozat azonosítója hiányzik.' using errcode = 'P0001';
  end if;

  perform public.admin_set_booking_series_group_rate(
    v_series_id,
    p_group_hourly_rate_huf,
    v_correlation_id
  );

  return v_result;
end;
$$;

revoke execute on function public.admin_create_booking_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint) from public, anon;
revoke execute on function public.admin_create_booking_series_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text,bigint) from public, anon;
grant execute on function public.admin_create_booking_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint) to authenticated, service_role;
grant execute on function public.admin_create_booking_series_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text,bigint) to authenticated, service_role;

comment on function public.admin_create_booking_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,bigint) is
  'Admin-only atomic booking creation plus Tréningterem group rate override. Any rate failure rolls back the booking creation.';
comment on function public.admin_create_booking_series_with_group_rate(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text,bigint) is
  'Admin-only atomic recurring-series creation plus Tréningterem group rate override. Any rate failure rolls back the entire series creation.';

commit;
