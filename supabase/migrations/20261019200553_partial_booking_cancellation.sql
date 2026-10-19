begin;

alter table public.bookings add column root_booking_id uuid references public.bookings(id) on delete restrict;
create index bookings_root_booking_idx on public.bookings(root_booking_id);
alter table public.bookings add constraint booking_root_not_self check(root_booking_id is distinct from id);
create table public.booking_partial_cancellations (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  root_booking_id uuid not null references public.bookings(id) on delete restrict,
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key uuid not null,
  removed_ranges jsonb not null,
  before_data jsonb not null,
  remaining_booking_ids uuid[] not null,
  reason text,
  created_at timestamptz not null default now(),
  unique(actor_user_id,idempotency_key)
);
alter table public.booking_partial_cancellations enable row level security;
revoke all on public.booking_partial_cancellations from public,anon,authenticated;
create trigger booking_partial_cancellations_immutable before update or delete on public.booking_partial_cancellations
for each row execute function public.prevent_audit_mutation();

create function public.guard_booking_fragment_group() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_root public.bookings%rowtype;
begin
  if tg_op='UPDATE' and new.root_booking_id is distinct from old.root_booking_id then
    raise exception 'A foglalás eredetkapcsolata nem módosítható.' using errcode='42501';
  end if;
  if new.root_booking_id is not null then
    select * into strict v_root from public.bookings b where b.id=new.root_booking_id;
    if v_root.root_booking_id is not null or v_root.user_id<>new.user_id
      or date_trunc('month',timezone('Europe/Budapest',v_root.start_at))<>date_trunc('month',timezone('Europe/Budapest',new.start_at)) then
      raise exception 'A foglalásrészek azonos felhasználóhoz és hónaphoz tartoznak.' using errcode='42501';
    end if;
  elsif tg_op='UPDATE' and exists(select 1 from public.bookings b where b.root_booking_id=old.id)
    and (new.user_id<>old.user_id or date_trunc('month',timezone('Europe/Budapest',new.start_at))<>date_trunc('month',timezone('Europe/Budapest',old.start_at))) then
    raise exception 'A felbontott foglalás felhasználója és hónapja nem módosítható.' using errcode='42501';
  end if;
  return new;
end $$;
create trigger bookings_fragment_group before insert or update on public.bookings
for each row execute function public.guard_booking_fragment_group();
revoke all on function public.guard_booking_fragment_group() from public,anon,authenticated,service_role;

-- Preserve the original cutoff trigger except during the new private,
-- transaction-bound operation. No user-controlled session flag grants bypass.
alter function public.guard_booking_update_cutoff() rename to guard_booking_update_cutoff_original;
revoke all on function public.guard_booking_update_cutoff_original() from public,anon,authenticated,service_role;
create function public.guard_booking_update_cutoff() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_role public.app_role; v_hours integer;
begin
  if old.status<>'active' or auth.uid() is null then return new; end if;
  select role into v_role from public.profiles where id=auth.uid() and is_active;
  if v_role is null then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  if v_role='admin' then return new; end if;
  if exists(select 1 from public.booking_operation_requests req
    where req.actor_user_id=auth.uid() and req.booking_id=old.id and req.result_payload is null
      and req.request_payload->>'operation'='partial_cancel'
      and req.request_payload->>'transaction_id'=txid_current()::text
      and (req.request_payload->>'expected_updated_at')::timestamptz=old.updated_at) then return new; end if;
  select (value#>>'{}')::integer into v_hours from public.app_settings where key='cancellation_cutoff_hours';
  if v_hours is null or v_hours<0 then raise exception 'Hibás lemondási határidő.' using errcode='P0001'; end if;
  if clock_timestamp()>old.start_at-make_interval(hours=>v_hours) then
    raise exception 'A foglalás % órán belül már nem módosítható.',v_hours using errcode='P0001';
  end if;
  return new;
end $$;
drop trigger bookings_guard_update_cutoff on public.bookings;
create trigger bookings_guard_update_cutoff before update of room_id,start_at,end_at,use_type,note on public.bookings
for each row when(old.status='active' and (old.room_id is distinct from new.room_id or old.start_at is distinct from new.start_at
or old.end_at is distinct from new.end_at or old.use_type is distinct from new.use_type or old.note is distinct from new.note))
execute function public.guard_booking_update_cutoff();
revoke all on function public.guard_booking_update_cutoff() from public,anon,authenticated,service_role;

create function public.cancel_booking_parts(p_booking_id uuid,p_expected_updated_at timestamptz,p_ranges jsonb,p_reason text,p_idempotency_key uuid)
returns uuid[] language plpgsql security definer set search_path='' as $$
declare
  v_actor public.profiles%rowtype; v_before public.bookings%rowtype; v_initial public.bookings%rowtype;
  v_req public.booking_operation_requests%rowtype; v_payload jsonb; v_canonical jsonb;
  v_removed tstzmultirange; v_remaining tstzmultirange; v_part tstzrange;
  v_root uuid; v_id uuid; v_ids uuid[]:='{}'; v_month date; v_hours integer; v_min integer; v_slot integer;
  v_first boolean:=true; v_reason text:=nullif(btrim(p_reason),'');
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active;
  if not found then raise exception 'Aktív bejelentkezés szükséges.' using errcode='42501'; end if;
  if p_booking_id is null or p_expected_updated_at is null or p_idempotency_key is null or jsonb_typeof(p_ranges) is distinct from 'array'
    or jsonb_array_length(p_ranges) not between 1 and 48 or length(coalesce(v_reason,''))>500 then
    raise exception 'Érvénytelen lemondási adatok.' using errcode='22023';
  end if;
  -- range constructor rejects reversed/empty endpoints; explicit finite and
  -- grid validation below runs before any write.
  if exists(select 1 from jsonb_array_elements(p_ranges) x where x->>'start' is null or x->>'end' is null
    or not isfinite((x->>'start')::timestamptz) or not isfinite((x->>'end')::timestamptz)
    or (x->>'end')::timestamptz<=(x->>'start')::timestamptz) then
    raise exception 'Érvénytelen lemondási időszak.' using errcode='22023';
  end if;
  select range_agg(tstzrange((x->>'start')::timestamptz,(x->>'end')::timestamptz,'[)')) into v_removed from jsonb_array_elements(p_ranges) x;
  select jsonb_agg(jsonb_build_object('start',lower(r),'end',upper(r)) order by lower(r)) into v_canonical from unnest(v_removed) r;
  v_payload:=jsonb_build_object('operation','partial_cancel','booking_id',p_booking_id,'expected_updated_at',p_expected_updated_at,'ranges',v_canonical,'reason',v_reason);
  select * into v_req from public.booking_operation_requests where actor_user_id=v_actor.id and idempotency_key=p_idempotency_key;
  if found then
    if v_req.request_payload-'transaction_id'=v_payload and v_req.result_payload is not null then
      return array(select jsonb_array_elements_text(v_req.result_payload->'booking_ids')::uuid);
    end if;
    raise exception 'A kérésazonosító már más művelethez tartozik.' using errcode='P0001';
  end if;
  select * into v_initial from public.bookings where id=p_booking_id;
  if not found or (v_actor.role<>'admin' and v_initial.user_id<>v_actor.id) then raise exception 'A foglalás nem kezelhető.' using errcode='42501'; end if;
  v_root:=coalesce(v_initial.root_booking_id,v_initial.id);
  perform pg_advisory_xact_lock(hashtextextended('booking-fragment:'||v_root::text,0));
  perform pg_advisory_xact_lock(hashtextextended(v_initial.room_id::text,0));
  begin
    insert into public.booking_operation_requests(actor_user_id,idempotency_key,operation,booking_id,request_payload)
      values(v_actor.id,p_idempotency_key,'update',p_booking_id,v_payload||jsonb_build_object('transaction_id',txid_current()::text));
  exception when unique_violation then
    select * into v_req from public.booking_operation_requests where actor_user_id=v_actor.id and idempotency_key=p_idempotency_key;
    if v_req.request_payload-'transaction_id'=v_payload and v_req.result_payload is not null then return array(select jsonb_array_elements_text(v_req.result_payload->'booking_ids')::uuid); end if;
    raise exception 'A kérésazonosító már más művelethez tartozik.' using errcode='P0001';
  end;
  -- Legacy series cancellation locks chronological rows, not UUID order.
  -- Never wait holding one fragment lock while requesting another: abort the
  -- whole operation cleanly if either row is busy, instead of forming a cycle.
  begin
    perform 1 from public.bookings b where b.id in(v_root,p_booking_id) order by b.id for no key update nowait;
  exception when lock_not_available then
    raise exception 'A foglalás másik műveletben módosul. Frissítsd az oldalt, majd próbáld újra.' using errcode='P0001';
  end;
  select * into v_before from public.bookings where id=p_booking_id;
  if v_before.status<>'active' or v_before.updated_at is distinct from p_expected_updated_at or v_before.room_id<>v_initial.room_id
    or v_before.start_at<>v_initial.start_at then raise exception 'A foglalás időközben módosult. Frissítsd az oldalt.' using errcode='P0001'; end if;
  v_month:=date_trunc('month',timezone('Europe/Budapest',v_before.start_at))::date;
  perform pg_advisory_xact_lock(hashtextextended('monthly-settlement-period:'||v_month::text,0));
  if exists(select 1 from public.monthly_settlement_periods where settlement_month=v_month)
    or exists(select 1 from public.monthly_settlements where settlement_month=v_month and is_closed) then
    raise exception 'Lezárt hónap foglalása nem bontható fel.' using errcode='42501';
  end if;
  select (value#>>'{}')::integer into v_hours from public.app_settings where key='cancellation_cutoff_hours';
  select (value#>>'{}')::integer into v_min from public.app_settings where key='minimum_booking_minutes';
  select (value#>>'{}')::integer into v_slot from public.app_settings where key='slot_minutes';
  if v_hours is null or v_hours<0 or v_min is null or v_min<=0 or v_slot is null or v_slot<=0 then raise exception 'Hiányos foglalási beállítás.' using errcode='P0001'; end if;
  foreach v_part in array array(select unnest(v_removed)) loop
    if not (v_part <@ tstzrange(v_before.start_at,v_before.end_at,'[)'))
      or extract(epoch from timezone('Europe/Budapest',lower(v_part))::time)%(v_slot*60)<>0
      or extract(epoch from timezone('Europe/Budapest',upper(v_part))::time)%(v_slot*60)<>0 then
      raise exception 'Csak a foglaláson belüli, időrácsra illeszkedő részek mondhatók le.' using errcode='22023';
    end if;
    if v_actor.role<>'admin' and clock_timestamp()>lower(v_part)-make_interval(hours=>v_hours) then
      raise exception 'A kijelölt rész % órán belül kezdődik, ezért nem mondható le.',v_hours using errcode='P0001';
    end if;
  end loop;
  v_remaining:=tstzmultirange(tstzrange(v_before.start_at,v_before.end_at,'[)'))-v_removed;
  if exists(select 1 from unnest(v_remaining) r where upper(r)-lower(r)<make_interval(mins=>v_min)) then
    raise exception 'A megmaradó foglalások legalább % percesek legyenek.',v_min using errcode='P0001';
  end if;
  if isempty(v_remaining) then
    update public.bookings set status='cancelled',updated_at=clock_timestamp() where id=p_booking_id;
    insert into public.booking_cancellations(booking_id,cancelled_by,minutes_before_start,reason,original_snapshot,idempotency_key,settlement_excluded)
      values(p_booking_id,v_actor.id,floor(extract(epoch from(v_before.start_at-clock_timestamp()))/60)::integer,v_reason,to_jsonb(v_before),p_idempotency_key,true);
  else
    for v_part in select unnest(v_remaining) order by 1 loop
      if v_first then
        update public.bookings set start_at=lower(v_part),end_at=upper(v_part),updated_at=clock_timestamp() where id=p_booking_id;
        v_id:=p_booking_id; v_first:=false;
      else
        insert into public.bookings(room_id,user_id,created_by,series_id,start_at,end_at,use_type,note,booking_title,status,idempotency_key,root_booking_id,
          hourly_rate_override_huf,hourly_rate_override_set_by,hourly_rate_override_set_at,hourly_rate_override_reason)
        values(v_before.room_id,v_before.user_id,v_before.created_by,v_before.series_id,lower(v_part),upper(v_part),v_before.use_type,v_before.note,v_before.booking_title,'active',gen_random_uuid(),v_root,
          v_before.hourly_rate_override_huf,v_before.hourly_rate_override_set_by,v_before.hourly_rate_override_set_at,v_before.hourly_rate_override_reason) returning id into v_id;
        if exists(select 1 from information_schema.columns where table_schema='public' and table_name='bookings' and column_name='group_hourly_rate_huf') then
          execute 'update public.bookings set group_hourly_rate_huf=($1->>''group_hourly_rate_huf'')::bigint where id=$2' using to_jsonb(v_before),v_id;
        end if;
      end if;
      v_ids:=array_append(v_ids,v_id);
    end loop;
  end if;
  insert into public.booking_partial_cancellations(booking_id,root_booking_id,actor_user_id,idempotency_key,removed_ranges,before_data,remaining_booking_ids,reason)
    values(p_booking_id,v_root,v_actor.id,p_idempotency_key,v_canonical,to_jsonb(v_before),v_ids,v_reason);
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
    values(v_actor.id,'booking.parts_cancelled','booking',p_booking_id::text,to_jsonb(v_before),jsonb_build_object('removed_ranges',v_canonical,'remaining_booking_ids',v_ids,'root_booking_id',v_root),v_reason,p_idempotency_key);
  insert into public.outbox_events(event_type,aggregate_type,aggregate_id,payload)
    values('booking.parts_cancelled','booking',p_booking_id::text,jsonb_build_object('booking_id',p_booking_id,'recipient_user_id',v_before.user_id,'removed_ranges',v_canonical,'remaining_booking_ids',v_ids));
  update public.booking_operation_requests set result_payload=jsonb_build_object('booking_ids',v_ids) where actor_user_id=v_actor.id and idempotency_key=p_idempotency_key;
  return v_ids;
end $$;
revoke all on function public.cancel_booking_parts(uuid,timestamptz,jsonb,text,uuid) from public,anon;
grant execute on function public.cancel_booking_parts(uuid,timestamptz,jsonb,text,uuid) to authenticated;

-- Group reads keep actual receipts immutable and count money only once.
alter function public.admin_booking_payment_context(uuid) rename to admin_booking_payment_context_single;
revoke all on function public.admin_booking_payment_context_single(uuid) from public,anon,authenticated,service_role;
create function public.admin_booking_payment_context(p_booking_id uuid)
returns table(booking_id uuid,user_name text,room_name text,start_at timestamptz,end_at timestamptz,booking_status public.booking_status,booking_title text,amount_huf bigint,paid_huf bigint,is_closed boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_root uuid;
begin
  perform public.require_active_admin();
  select coalesce(b.root_booking_id,b.id) into v_root from public.bookings b where b.id=p_booking_id;
  return query select p_booking_id,min(c.user_name),min(c.room_name),min(c.start_at),max(c.end_at),
    case when bool_or(c.booking_status='active') then 'active'::public.booking_status else 'cancelled'::public.booking_status end,
    min(c.booking_title),sum(c.amount_huf)::bigint,sum(c.paid_huf)::bigint,bool_or(c.is_closed)
  from public.bookings b cross join lateral public.admin_booking_payment_context_single(b.id) c
  where coalesce(b.root_booking_id,b.id)=v_root
  having count(*)>0;
end $$;
grant execute on function public.admin_booking_payment_context(uuid) to authenticated;
revoke all on function public.admin_booking_payment_context(uuid) from public,anon;

create or replace function public.admin_booking_payment_history(p_booking_id uuid)
returns table(payment_id uuid,amount_huf bigint,paid_on date,method public.payment_method,destination public.money_destination,admin_note text,void_reason text)
language plpgsql stable security definer set search_path='' as $$
declare v_root uuid;
begin
  perform public.require_active_admin();
  select coalesce(b.root_booking_id,b.id) into v_root from public.bookings b where b.id=p_booking_id;
  return query select py.id,py.amount_huf,py.paid_on,py.method,py.destination,py.admin_note,pv.reason
  from public.payments py join public.bookings b on b.id=py.booking_id left join public.payment_voids pv on pv.payment_id=py.id
  where coalesce(b.root_booking_id,b.id)=v_root order by py.paid_on desc,py.created_at desc,py.id;
end $$;

alter function public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) rename to admin_record_booking_payment_single;
revoke all on function public.admin_record_booking_payment_single(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) from public,anon,authenticated,service_role;
create function public.admin_record_booking_payment(p_booking_id uuid,p_amount_huf bigint,p_paid_on date,p_method public.payment_method,p_destination public.money_destination,p_admin_note text,p_idempotency_key uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_root uuid; v_id uuid; v_existing public.payments%rowtype;
begin
  perform public.require_active_admin();
  select coalesce(b.root_booking_id,b.id) into v_root from public.bookings b where b.id=p_booking_id;
  if v_root is null then raise exception 'A foglalás nem található.' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended('booking-fragment:'||v_root::text,0));
  select * into v_existing from public.payments where idempotency_key=p_idempotency_key;
  if found then
    if not exists(select 1 from public.bookings b where b.id=v_existing.booking_id and coalesce(b.root_booking_id,b.id)=v_root) then
      raise exception 'Az idempotencia kulcs másik foglaláshoz tartozik.' using errcode='P0001';
    end if;
    v_id:=v_existing.booking_id;
  else
    select b.id into v_id from public.bookings b where coalesce(b.root_booking_id,b.id)=v_root and b.status='active'
      order by (b.id=v_root) desc,b.start_at,b.id limit 1;
    if v_id is null then raise exception 'Teljesen lemondott foglalásra új befizetés nem rögzíthető.' using errcode='P0001'; end if;
  end if;
  return public.admin_record_booking_payment_single(v_id,p_amount_huf,p_paid_on,p_method,p_destination,p_admin_note,p_idempotency_key);
end $$;
revoke all on function public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) from public,anon;
grant execute on function public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) to authenticated;

drop function public.admin_booking_payment_totals(date);
create function public.admin_booking_payment_totals(p_month date)
returns table(booking_id uuid,paid_huf bigint,payment_group_id uuid,group_due_huf bigint,group_paid_huf bigint,is_group_anchor boolean)
language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_active_admin();
  if p_month is null or p_month<>date_trunc('month',p_month)::date then raise exception 'Érvénytelen hónap.' using errcode='22023'; end if;
  return query with members as (
    select b.*,coalesce(b.root_booking_id,b.id) root from public.bookings b
    where date_trunc('month',timezone('Europe/Budapest',b.start_at))::date=p_month
  ), groups as (
    select distinct m.root from members m
  ), balances as (
    select g.root,c.amount_huf,c.paid_huf from groups g cross join lateral public.admin_booking_payment_context(g.root) c
  ), anchors as (
    select distinct on(m.root) m.root,m.id from members m order by m.root,(m.status='active') desc,(m.id=m.root) desc,m.start_at,m.id
  ) select m.id,case when a.id=m.id then c.paid_huf else 0 end::bigint,
    case when m.root_booking_id is not null or exists(select 1 from members x where x.root_booking_id=m.id) then m.root else null end,
    c.amount_huf,c.paid_huf,a.id=m.id
  from members m join balances c on c.root=m.root join anchors a on a.root=m.root;
end $$;
revoke all on function public.admin_booking_payment_totals(date) from public,anon;
grant execute on function public.admin_booking_payment_totals(date) to authenticated;

create or replace function public.monthly_settlement_cutoff_blockers(p_month date,p_as_of timestamptz)
returns bigint language plpgsql stable security definer set search_path='' as $$
declare v_hours integer; v_slot integer; v_min integer; v_count bigint;
begin
  if p_month is null or p_as_of is null then raise exception 'A hónap és az időpont kötelező.' using errcode='22004'; end if;
  select (value#>>'{}')::integer into v_hours from public.app_settings where key='cancellation_cutoff_hours';
  select (value#>>'{}')::integer into v_slot from public.app_settings where key='slot_minutes';
  select (value#>>'{}')::integer into v_min from public.app_settings where key='minimum_booking_minutes';
  if v_hours is null or v_hours<0 or v_slot is null or v_slot<=0 or v_min is null or v_min<=0 then raise exception 'Hibás foglalási beállítás.' using errcode='P0001'; end if;
  select count(*) into v_count from public.bookings b where b.status='active'
    and (b.start_at at time zone 'Europe/Budapest')::date>=p_month
    and (b.start_at at time zone 'Europe/Budapest')::date<(p_month+interval '1 month')::date
    and case when b.end_at-b.start_at>=make_interval(mins=>v_min+v_slot) then b.end_at-make_interval(mins=>v_slot) else b.start_at end
      >=p_as_of+make_interval(hours=>v_hours);
  return v_count;
end $$;

-- A fragmented occurrence is an explicit exception: keep ordinary series
-- operations unchanged for unfragmented series, but never flatten its gaps.
create function public.guard_fragmented_series_edit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if old.series_id is not null and (old.root_booking_id is not null or exists(select 1 from public.bookings b where b.root_booking_id=old.id))
    and exists(select 1 from public.booking_scope_operations req where req.actor_user_id=auth.uid()
      and req.result_payload is null and req.action='update' and req.scope in('following','series')) then
    raise exception 'A felbontott sorozatalkalom csak részenként szerkeszthető; a sorozat egészének törlése továbbra is elérhető.' using errcode='P0001';
  end if;
  return new;
end $$;
create trigger bookings_fragmented_series_edit before update of start_at,end_at,room_id,use_type on public.bookings
for each row execute function public.guard_fragmented_series_edit();
revoke all on function public.guard_fragmented_series_edit() from public,anon,authenticated,service_role;

create function public.booking_cancellation_event_rows(p_start date,p_end date,p_user uuid default null)
returns table(booking_id uuid,root_id uuid,user_id uuid,room_id uuid,start_at timestamptz,end_at timestamptz,cancelled_at timestamptz,actor_id uuid,reason text,minutes_before_start integer)
language sql stable security definer set search_path='' as $$
  select b.id,coalesce(b.root_booking_id,b.id),b.user_id,b.room_id,b.start_at,b.end_at,c.cancelled_at,c.cancelled_by,c.reason,c.minutes_before_start
  from public.bookings b left join public.booking_cancellations c on c.booking_id=b.id
  where b.status='cancelled' and (b.start_at at time zone 'Europe/Budapest')::date>=p_start
    and (b.start_at at time zone 'Europe/Budapest')::date<p_end and (p_user is null or b.user_id=p_user)
  union all
  select pc.booking_id,pc.root_booking_id,(pc.before_data->>'user_id')::uuid,(pc.before_data->>'room_id')::uuid,
    (r->>'start')::timestamptz,(r->>'end')::timestamptz,pc.created_at,pc.actor_user_id,pc.reason,
    floor(extract(epoch from((r->>'start')::timestamptz-pc.created_at))/60)::integer
  from public.booking_partial_cancellations pc cross join lateral jsonb_array_elements(pc.removed_ranges) r
  where cardinality(pc.remaining_booking_ids)>0 and ((r->>'start')::timestamptz at time zone 'Europe/Budapest')::date>=p_start
    and ((r->>'start')::timestamptz at time zone 'Europe/Budapest')::date<p_end
    and (p_user is null or (pc.before_data->>'user_id')::uuid=p_user);
$$;
revoke all on function public.booking_cancellation_event_rows(date,date,uuid) from public,anon,authenticated,service_role;

create or replace function public.admin_cancellation_summary(p_end_month date,p_months integer)
returns table(user_id uuid,user_name text,total_bookings bigint,cancelled_count bigint,cancelled_hours numeric,user_cancelled_count bigint,user_cancelled_hours numeric,cancellation_rate numeric)
language plpgsql stable security definer set search_path='' as $$
declare v_start date; v_end date;
begin
  perform public.require_active_admin();
  if p_end_month is null then raise exception 'A záró hónap kötelező.' using errcode='22004'; end if;
  if p_months not in(1,3,6,12) then raise exception 'Az időszak csak 1, 3, 6 vagy 12 hónap lehet.' using errcode='22023'; end if;
  v_end:=(date_trunc('month',p_end_month)+interval '1 month')::date;
  v_start:=(v_end-make_interval(months=>p_months))::date;
  return query with totals as (
    select b.user_id,count(distinct coalesce(b.root_booking_id,b.id)) total
    from public.bookings b where (b.start_at at time zone 'Europe/Budapest')::date>=v_start
      and (b.start_at at time zone 'Europe/Budapest')::date<v_end group by b.user_id
  ), events as (
    select e.user_id,count(distinct e.root_id) cancelled,
      round(sum(extract(epoch from(e.end_at-e.start_at)))/3600,2) hours,
      count(distinct e.root_id) filter(where e.actor_id=e.user_id) user_cancelled,
      round(coalesce(sum(extract(epoch from(e.end_at-e.start_at))) filter(where e.actor_id=e.user_id),0)/3600,2) user_hours
    from public.booking_cancellation_event_rows(v_start,v_end,null) e group by e.user_id
  ) select p.id,p.last_name||' '||p.first_name,t.total,coalesce(e.cancelled,0),coalesce(e.hours,0),coalesce(e.user_cancelled,0),coalesce(e.user_hours,0),
    round(100.0*coalesce(e.user_cancelled,0)/t.total,1)
  from totals t join public.profiles p on p.id=t.user_id left join events e on e.user_id=t.user_id
  order by p.last_name,p.first_name,p.id;
end $$;

create or replace function public.admin_cancellation_details(p_end_month date,p_months integer,p_user_id uuid default null)
returns table(booking_id uuid,user_id uuid,user_name text,booking_date date,room_name text,start_time time,end_time time,cancelled_hours numeric,cancelled_at timestamptz,minutes_before_start integer,cancellation_reason text,cancelled_by_user boolean,cancelled_by_name text)
language plpgsql stable security definer set search_path='' as $$
declare v_start date; v_end date;
begin
  perform public.require_active_admin();
  if p_end_month is null then raise exception 'A záró hónap kötelező.' using errcode='22004'; end if;
  if p_months not in(1,3,6,12) then raise exception 'Az időszak csak 1, 3, 6 vagy 12 hónap lehet.' using errcode='22023'; end if;
  v_end:=(date_trunc('month',p_end_month)+interval '1 month')::date; v_start:=(v_end-make_interval(months=>p_months))::date;
  return query select e.booking_id,e.user_id,p.last_name||' '||p.first_name,(e.start_at at time zone 'Europe/Budapest')::date,r.name,
    (e.start_at at time zone 'Europe/Budapest')::time,(e.end_at at time zone 'Europe/Budapest')::time,
    round(extract(epoch from(e.end_at-e.start_at))/3600,2),e.cancelled_at,e.minutes_before_start,e.reason,e.actor_id=e.user_id,a.last_name||' '||a.first_name
  from public.booking_cancellation_event_rows(v_start,v_end,p_user_id) e
  join public.profiles p on p.id=e.user_id join public.rooms r on r.id=e.room_id left join public.profiles a on a.id=e.actor_id
  order by p.last_name,p.first_name,e.start_at,e.cancelled_at,e.booking_id;
end $$;
commit;
