begin;

-- Restore the pre-title RPC signatures without reintroducing overload ambiguity.
-- The title-aware signatures remain separate explicit APIs, so remove their defaults.

create or replace function public.create_booking(
  p_room_id uuid, p_user_id uuid, p_start_at timestamptz, p_end_at timestamptz,
  p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid, p_booking_title text
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'create',p_booking_title);
  v_id := public.create_booking_base(p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=v_id and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking.title_set','booking',v_id::text,jsonb_build_object('booking_title_changed',true),p_idempotency_key);
  end if;
  return v_id;
end; $$;

create or replace function public.update_booking(
  p_booking_id uuid, p_expected_updated_at timestamptz, p_room_id uuid, p_start_at timestamptz,
  p_end_at timestamptz, p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid,
  p_booking_title text
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'update',p_booking_title);
  v_id := public.update_booking_base(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=v_id and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking.title_changed','booking',v_id::text,jsonb_build_object('booking_title_changed',true),p_idempotency_key);
  end if;
  return v_id;
end; $$;

create or replace function public.update_booking_scope(
  p_booking_id uuid, p_scope text, p_expected_updated_at timestamptz, p_room_id uuid,
  p_start_at timestamptz, p_end_at timestamptz, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid, p_booking_title text
) returns integer language plpgsql security definer set search_path='' as $$
declare v_selected public.bookings%rowtype; v_ids uuid[]; v_count integer; v_title text;
begin
  select * into v_selected from public.bookings where id=p_booking_id;
  if not found then raise exception 'A foglalás nem található.' using errcode='P0001'; end if;
  if v_selected.series_id is null then
    perform public.update_booking(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,p_booking_title);
    return 1;
  end if;
  v_title := public.claim_booking_title_request(p_idempotency_key,'scope_update',p_booking_title);
  select array_agg(b.id order by b.start_at,b.id) into v_ids
  from public.bookings b
  where b.series_id=v_selected.series_id and b.status='active' and b.start_at>clock_timestamp()
    and (p_scope='series' or (p_scope='following' and b.start_at>=v_selected.start_at) or (p_scope='occurrence' and b.id=p_booking_id));
  v_count := public.update_booking_scope_base(p_booking_id,p_scope,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=any(coalesce(v_ids,'{}'::uuid[])) and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking_series.title_changed','booking_series',v_selected.series_id::text,jsonb_build_object('scope',p_scope,'booking_title_changed',true),p_idempotency_key);
  end if;
  return v_count;
end; $$;

create or replace function public.create_booking_series(
  p_room_id uuid, p_user_id uuid, p_first_start_at timestamptz, p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency, p_ends_on date, p_occurrence_count integer,
  p_exception_dates date[], p_conflict_policy public.conflict_policy, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid, p_booking_title text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_series_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'series_create',p_booking_title);
  v_result := public.create_booking_series_base(p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key);
  v_series_id := (v_result->>'series_id')::uuid;
  update public.booking_series set booking_title=v_title where id=v_series_id and booking_title is distinct from v_title;
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp() where series_id=v_series_id and booking_title is distinct from v_title;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
  values(auth.uid(),'booking_series.title_set','booking_series',v_series_id::text,jsonb_build_object('booking_title_changed',v_title is not null),p_idempotency_key);
  return v_result;
end; $$;

create or replace function public.create_booking(
  p_room_id uuid, p_user_id uuid, p_start_at timestamptz, p_end_at timestamptz,
  p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid
) returns uuid language sql security definer set search_path='' as $$
  select public.create_booking(p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,null::text);
$$;

create or replace function public.update_booking(
  p_booking_id uuid, p_expected_updated_at timestamptz, p_room_id uuid, p_start_at timestamptz,
  p_end_at timestamptz, p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid
) returns uuid language sql security definer set search_path='' as $$
  select public.update_booking(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,null::text);
$$;

create or replace function public.update_booking_scope(
  p_booking_id uuid, p_scope text, p_expected_updated_at timestamptz, p_room_id uuid,
  p_start_at timestamptz, p_end_at timestamptz, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid
) returns integer language sql security definer set search_path='' as $$
  select public.update_booking_scope(p_booking_id,p_scope,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,null::text);
$$;

create or replace function public.create_booking_series(
  p_room_id uuid, p_user_id uuid, p_first_start_at timestamptz, p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency, p_ends_on date, p_occurrence_count integer,
  p_exception_dates date[], p_conflict_policy public.conflict_policy, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid
) returns jsonb language sql security definer set search_path='' as $$
  select public.create_booking_series(p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key,null::text);
$$;

revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) from public, anon;
revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) from public, anon;
revoke all on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) from public, anon;

grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) to authenticated, service_role;
grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) to authenticated, service_role;

commit;
