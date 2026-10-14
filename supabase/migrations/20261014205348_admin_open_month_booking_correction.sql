begin;

-- Dedicated single-occurrence correction: do not loosen the pricing setter,
-- normal-user cutoff, historical series operations or closed snapshot guards.
create function public.admin_correct_open_month_booking(
  p_booking_id uuid,p_expected_updated_at timestamptz,p_room_id uuid,
  p_start_at timestamptz,p_end_at timestamptz,p_use_type public.booking_use_type,
  p_note text,p_idempotency_key uuid,p_booking_title text,p_reason text
) returns uuid language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid:=public.require_active_admin();
  v_initial public.bookings%rowtype;
  v_before public.bookings%rowtype;
  v_after public.bookings%rowtype;
  v_existing public.booking_operation_requests%rowtype;
  v_months date[];
  v_month date;
  v_lock bigint;
  v_reason text:=nullif(trim(coalesce(p_reason,'')),'');
  v_note text:=nullif(trim(coalesce(p_note,'')),'');
  v_title text:=nullif(trim(coalesce(p_booking_title,'')),'');
  v_request jsonb;
begin
  if p_booking_id is null or p_expected_updated_at is null or p_room_id is null
     or p_start_at is null or p_end_at is null or p_use_type is null or p_idempotency_key is null
     or not isfinite(p_start_at) or not isfinite(p_end_at)
     or v_reason is null or length(v_reason)>300 or length(coalesce(v_title,''))>100 or length(coalesce(v_note,''))>1000 then
    raise exception 'A korrekció kötelező adatai vagy indoka hiányoznak/hibásak.' using errcode='22023';
  end if;
  v_request:=jsonb_build_object('operation','open_month_admin_correction','booking_id',p_booking_id,
    'expected_updated_at',p_expected_updated_at,'room_id',p_room_id,'start_at',p_start_at,'end_at',p_end_at,
    'use_type',p_use_type,'note',v_note,'booking_title',v_title,'reason',v_reason);
  select * into v_existing from public.booking_operation_requests req
    where req.actor_user_id=v_actor and req.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_payload=v_request and v_existing.result_payload is not null then return p_booking_id; end if;
    raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode='P0001';
  end if;
  select * into v_initial from public.bookings b where b.id=p_booking_id;
  if not found then raise exception 'A foglalás nem található.' using errcode='P0001'; end if;
  for v_lock in select distinct value from unnest(array[pg_catalog.hashtextextended(v_initial.room_id::text,0),pg_catalog.hashtextextended(p_room_id::text,0)]) locks(value) order by value loop
    perform pg_catalog.pg_advisory_xact_lock(v_lock);
  end loop;
  -- Existing ledger is admin-private and rejects retries with altered reasons.
  begin
    insert into public.booking_operation_requests(actor_user_id,idempotency_key,operation,booking_id,request_payload)
    values(v_actor,p_idempotency_key,'update',p_booking_id,v_request);
  exception when unique_violation then
    select * into v_existing from public.booking_operation_requests req where req.actor_user_id=v_actor and req.idempotency_key=p_idempotency_key;
    if v_existing.request_payload=v_request and v_existing.result_payload is not null then return p_booking_id; end if;
    raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode='P0001';
  end;
  select * into v_before from public.bookings b where b.id=p_booking_id for no key update;
  if v_before.updated_at is distinct from p_expected_updated_at or v_before.room_id is distinct from v_initial.room_id
     or v_before.start_at is distinct from v_initial.start_at then
    raise exception 'A foglalás időközben módosult. Frissítsd az oldalt, majd próbáld újra.' using errcode='P0001';
  end if;
  if v_before.status<>'active' or v_before.start_at>clock_timestamp() then
    raise exception 'Ez a korrekció csak megkezdett vagy múltbeli aktív foglaláshoz használható.' using errcode='P0001';
  end if;
  v_months:=array[date_trunc('month',timezone('Europe/Budapest',v_initial.start_at))::date,
    date_trunc('month',timezone('Europe/Budapest',p_start_at))::date];
  -- Existing writers acquire room/booking before publication locks.
  -- NO KEY UPDATE permits close snapshot FK KEY SHARE while we wait.
  for v_month in select distinct value from unnest(v_months) months(value) order by value loop
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('monthly-settlement-period:'||v_month::text,0));
  end loop;
  if exists(select 1 from public.monthly_settlement_periods period where period.settlement_month=any(v_months))
     or exists(select 1 from public.monthly_settlements ms where ms.settlement_month=any(v_months) and ms.is_closed) then
    raise exception 'Lezárt hónap foglalása ezzel a művelettel nem módosítható.' using errcode='42501';
  end if;
  perform public.assert_booking_request(v_actor,p_room_id,v_before.user_id,p_start_at,p_end_at,p_use_type);
  begin
    update public.bookings set room_id=p_room_id,start_at=p_start_at,end_at=p_end_at,use_type=p_use_type,
      note=v_note,booking_title=v_title,updated_at=clock_timestamp()
    where id=p_booking_id returning * into v_after;
  exception when exclusion_violation then
    raise exception 'A helyiség a kiválasztott időpontban már foglalt.' using errcode='P0001';
  end;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
    values(v_actor,'booking.updated','booking',p_booking_id::text,to_jsonb(v_before),to_jsonb(v_after),v_reason,p_idempotency_key);
  insert into public.outbox_events(event_type,aggregate_type,aggregate_id,payload)
    values('booking.updated','booking',p_booking_id::text,jsonb_build_object('booking_id',p_booking_id,'recipient_user_id',v_before.user_id));
  update public.booking_operation_requests set result_payload=jsonb_build_object('booking_id',p_booking_id,'updated_at',v_after.updated_at)
    where actor_user_id=v_actor and idempotency_key=p_idempotency_key;
  return p_booking_id;
end; $$;

revoke all on function public.admin_correct_open_month_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,text) from public,anon;
grant execute on function public.admin_correct_open_month_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,text) to authenticated;
comment on function public.admin_correct_open_month_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text,text)
is 'Admin-only, reasoned, idempotent single-occurrence historical correction in open source/target months. Booking rate override, series identity and actual receipts remain unchanged.';
commit;
