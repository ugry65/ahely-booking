begin;

-- One receipt, one monthly ledger entry. Booking allocation is optional for
-- historical monthly receipts. No business data is backfilled by this migration.
alter table public.payments add column booking_id uuid references public.bookings(id) on delete restrict;
create index payments_booking_idx on public.payments(booking_id);
create table public.payment_voids (
  payment_id uuid primary key references public.payments(id) on delete restrict,
  reason text not null check (length(trim(reason)) between 1 and 300),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
alter table public.payment_voids enable row level security;
revoke all on public.payment_voids from public, anon, authenticated;
create trigger payment_voids_immutable before update or delete on public.payment_voids
for each row execute function public.prevent_audit_mutation();
create trigger payments_immutable before update on public.payments
for each row execute function public.prevent_audit_mutation();

create function public.admin_record_booking_payment(
  p_booking_id uuid, p_amount_huf bigint, p_paid_on date,
  p_method public.payment_method, p_destination public.money_destination,
  p_admin_note text, p_idempotency_key uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.require_active_admin();
  v_booking public.bookings%rowtype;
  v_month date;
  v_settlement uuid;
  v_existing public.payments%rowtype;
  v_payment uuid;
  v_note text := nullif(trim(coalesce(p_admin_note, '')), '');
begin
  if p_amount_huf is null or p_amount_huf <= 0 or p_amount_huf > 100000000
     or p_paid_on is null or p_paid_on > timezone('Europe/Budapest', now())::date
     or p_method is null or p_destination is null or p_idempotency_key is null
     or length(coalesce(v_note, '')) > 300 then
    raise exception 'Érvénytelen befizetési összeg, dátum vagy fizetési adatok.' using errcode='22023';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('payment-request:' || p_idempotency_key::text, 0));
  -- Lock the booking against owner/month changes while allocating money.
  select * into v_booking from public.bookings b where b.id=p_booking_id for no key update;
  if not found then raise exception 'A foglalás nem található.' using errcode='P0001'; end if;
  select * into v_existing from public.payments py where py.idempotency_key=p_idempotency_key;
  if found then
    if exists(select 1 from public.payment_voids pv where pv.payment_id=v_existing.id) then
      raise exception 'Ez a befizetési kérés már érvénytelenítve lett. Új rögzítés szükséges.' using errcode='P0001';
    end if;
    if v_existing.booking_id is distinct from p_booking_id or v_existing.amount_huf<>p_amount_huf
       or v_existing.paid_on<>p_paid_on or v_existing.method<>p_method
       or v_existing.destination<>p_destination or v_existing.admin_note is distinct from v_note then
      raise exception 'Az idempotencia kulcs már másik befizetéshez tartozik.' using errcode='P0001';
    end if;
    return v_existing.id;
  end if;
  if v_booking.status <> 'active' then raise exception 'Lemondott foglalásra új befizetés nem rögzíthető.' using errcode='P0001'; end if;
  v_month := date_trunc('month', timezone('Europe/Budapest', v_booking.start_at))::date;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_booking.user_id::text || ':' || v_month::text, 0));
  insert into public.monthly_settlements(user_id, settlement_month) values(v_booking.user_id, v_month)
    on conflict(user_id, settlement_month) do nothing;
  select ms.id into v_settlement from public.monthly_settlements ms
    where ms.user_id=v_booking.user_id and ms.settlement_month=v_month;
  insert into public.payments(settlement_id,booking_id,amount_huf,paid_on,method,destination,admin_note,idempotency_key,created_by)
    values(v_settlement,p_booking_id,p_amount_huf,p_paid_on,p_method,p_destination,v_note,p_idempotency_key,v_actor)
    returning id into v_payment;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,reason,correlation_id)
    values(v_actor,'booking_payment.created','payment',v_payment::text,
      jsonb_build_object('booking_id',p_booking_id,'settlement_id',v_settlement,'amount_huf',p_amount_huf,'paid_on',p_paid_on,'method',p_method,'destination',p_destination),
      'Foglalási befizetés rögzítése',p_idempotency_key);
  return v_payment;
end; $$;

create function public.admin_void_booking_payment(p_payment_id uuid,p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := public.require_active_admin();
  v_payment public.payments%rowtype;
  v_existing public.payment_voids%rowtype;
  v_settlement public.monthly_settlements%rowtype;
  v_reason text := trim(coalesce(p_reason,''));
begin
  if length(v_reason) not between 1 and 300 then raise exception 'A javítás indoka kötelező (legfeljebb 300 karakter).' using errcode='22023'; end if;
  select ms.* into v_settlement from public.payments py join public.monthly_settlements ms on ms.id=py.settlement_id where py.id=p_payment_id;
  if not found then raise exception 'A befizetés nem található.' using errcode='P0001'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_settlement.user_id::text || ':' || v_settlement.settlement_month::text,0));
  select * into v_payment from public.payments py where py.id=p_payment_id for update;
  if not found or v_payment.booking_id is null then raise exception 'A foglalási befizetés nem található.' using errcode='P0001'; end if;
  select * into v_existing from public.payment_voids pv where pv.payment_id=p_payment_id;
  if found then
    if v_existing.reason<>v_reason then raise exception 'A befizetés már más indokkal érvénytelenítve van.' using errcode='P0001'; end if;
    return;
  end if;
  insert into public.payment_voids(payment_id,reason,created_by) values(p_payment_id,v_reason,v_actor);
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,reason,correlation_id)
    values(v_actor,'booking_payment.voided','payment',p_payment_id::text,jsonb_build_object('amount_huf',v_payment.amount_huf),v_reason,extensions.gen_random_uuid());
end; $$;

-- A receipt remains allocated to its original person/month. Cancellation keeps
-- the credit; moving money to another person/month requires explicit correction.
create function public.guard_booking_payment_allocation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.user_id is distinct from old.user_id
    or date_trunc('month',timezone('Europe/Budapest',new.start_at)) is distinct from date_trunc('month',timezone('Europe/Budapest',old.start_at)))
    and exists(select 1 from public.payments py where py.booking_id=old.id
      and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id)) then
    raise exception 'A befizetett foglalás felhasználója vagy hónapja csak a befizetés külön rendezése után változtatható.' using errcode='P0001';
  end if;
  return new;
end; $$;
create trigger bookings_payment_allocation before update on public.bookings
for each row execute function public.guard_booking_payment_allocation();

create function public.guard_payment_booking_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype;
begin
  if new.booking_id is not null then
    select * into v_booking from public.bookings b where b.id=new.booking_id for share;
    if not found or not exists(select 1 from public.monthly_settlements ms where ms.id=new.settlement_id and ms.user_id=v_booking.user_id
      and ms.settlement_month=date_trunc('month',timezone('Europe/Budapest',v_booking.start_at))::date) then
      raise exception 'A befizetés foglalási és havi hozzárendelése eltér.' using errcode='22023';
    end if;
  end if;
  return new;
end; $$;
create trigger payments_booking_allocation before insert on public.payments
for each row execute function public.guard_payment_booking_insert();
revoke all on function public.guard_payment_booking_insert() from public,anon,authenticated,service_role;

create function public.admin_booking_payment_history(p_booking_id uuid)
returns table(payment_id uuid,amount_huf bigint,paid_on date,method public.payment_method,destination public.money_destination,admin_note text,void_reason text)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_active_admin();
  return query select py.id,py.amount_huf,py.paid_on,py.method,py.destination,py.admin_note,pv.reason
    from public.payments py left join public.payment_voids pv on pv.payment_id=py.id
    where py.booking_id=p_booking_id order by py.paid_on desc,py.created_at desc,py.id;
end; $$;

create function public.admin_booking_payment_totals(p_month date)
returns table(booking_id uuid,paid_huf bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_active_admin();
  if p_month is null or p_month<>date_trunc('month',p_month)::date then raise exception 'Érvénytelen hónap.' using errcode='22023'; end if;
  return query select py.booking_id,sum(py.amount_huf)::bigint from public.payments py
    join public.monthly_settlements ms on ms.id=py.settlement_id
    where ms.settlement_month=p_month and py.booking_id is not null
      and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id)
    group by py.booking_id;
end; $$;

create function public.admin_booking_payment_context(p_booking_id uuid)
returns table(booking_id uuid,user_name text,room_name text,start_at timestamptz,end_at timestamptz,booking_status public.booking_status,booking_title text,amount_huf bigint,paid_huf bigint,is_closed boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_booking public.bookings%rowtype; v_month date;
begin
  perform public.require_active_admin();
  select * into v_booking from public.bookings b where b.id=p_booking_id;
  if not found then return; end if;
  v_month:=date_trunc('month',timezone('Europe/Budapest',v_booking.start_at))::date;
  return query select b.id,trim(concat_ws(' ',p.last_name,p.first_name)),r.name,b.start_at,b.end_at,b.status,b.booking_title,
    case when ms.is_closed then coalesce((select line.amount_huf from public.settlement_booking_lines line where line.settlement_revision_id=ms.closed_revision_id and line.booking_id=b.id),0)
      when b.status='active' then (select round(extract(epoch from (b.end_at-b.start_at))/3600*rate.hourly_rate_huf)::bigint from public.resolve_booking_applied_rate(b.id,public.month_normal_minutes(b.user_id,v_month)) rate)
      else 0 end::bigint,
    coalesce((select sum(py.amount_huf) from public.payments py where py.booking_id=b.id and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id)),0)::bigint,
    exists(select 1 from public.monthly_settlement_periods period where period.settlement_month=v_month)
    from public.bookings b join public.profiles p on p.id=b.user_id join public.rooms r on r.id=b.room_id
    left join public.monthly_settlements ms on ms.user_id=b.user_id and ms.settlement_month=v_month
    where b.id=p_booking_id;
end; $$;

revoke all on function public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) from public,anon;
revoke all on function public.admin_void_booking_payment(uuid,text) from public,anon;
revoke all on function public.admin_booking_payment_history(uuid) from public,anon;
revoke all on function public.admin_booking_payment_totals(date) from public,anon;
revoke all on function public.admin_booking_payment_context(uuid) from public,anon;
revoke all on function public.guard_booking_payment_allocation() from public,anon,authenticated,service_role;
grant execute on function public.admin_record_booking_payment(uuid,bigint,date,public.payment_method,public.money_destination,text,uuid) to authenticated;
grant execute on function public.admin_void_booking_payment(uuid,text) to authenticated;
grant execute on function public.admin_booking_payment_history(uuid) to authenticated;
grant execute on function public.admin_booking_payment_totals(date) to authenticated;
grant execute on function public.admin_booking_payment_context(uuid) to authenticated;

create function public.admin_monthly_booking_payment_summary(p_month date)
returns table(user_id uuid,user_name text,due_huf bigint,paid_huf bigint,remaining_huf bigint,overpaid_huf bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_active_admin();
  return query select s.user_id,s.user_name,s.due_huf,s.paid_huf,s.remaining_huf,
    greatest(s.paid_huf-s.due_huf,0)::bigint
    from public.admin_monthly_payment_summary(p_month) s;
end; $$;
revoke all on function public.admin_monthly_booking_payment_summary(date) from public,anon;
grant execute on function public.admin_monthly_booking_payment_summary(date) to authenticated;

create or replace function public.admin_monthly_payment_summary(p_month date)
returns table (
  user_id uuid,
  user_name text,
  settlement_month date,
  due_huf bigint,
  paid_huf bigint,
  remaining_huf bigint,
  payment_status public.payment_status,
  is_closed boolean,
  invoice_requested boolean,
  invoice_number text,
  last_payment_on date
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();

  if p_month is null or p_month <> date_trunc('month', p_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  return query
  with live as (
    select * from public.admin_monthly_pricing_summary(p_month)
  ),
  ids as (
    select l.user_id from live l
    union
    select ms.user_id from public.monthly_settlements ms where ms.settlement_month = p_month
  ),
  base as (
    select
      i.user_id,
      trim(concat_ws(' ', p.last_name, p.first_name))::text as user_name,
      ms.id as settlement_id,
      coalesce(ms.settlement_month, p_month) as settlement_month,
      coalesce(ms.is_closed, false) as is_closed,
      coalesce(ms.invoice_requested, false) as invoice_requested,
      ms.invoice_number,
      ms.status as stored_status,
      case
        when ms.closed_revision_id is not null then sr.calculated_due_huf
        else coalesce((select c.calculated_due_huf from public.calculate_monthly_pricing(i.user_id,p_month) c), 0)
      end::bigint as base_due_huf
    from ids i
    join public.profiles p on p.id = i.user_id
    left join live l on l.user_id = i.user_id
    left join public.monthly_settlements ms on ms.user_id = i.user_id and ms.settlement_month = p_month
    left join public.settlement_revisions sr on sr.id = ms.closed_revision_id
  )
  select
    b.user_id,
    b.user_name,
    b.settlement_month,
    greatest(b.base_due_huf + coalesce(a.adjustment_huf, 0), 0)::bigint as due_huf,
    coalesce(pay.paid_huf, 0)::bigint as paid_huf,
    greatest(greatest(b.base_due_huf + coalesce(a.adjustment_huf, 0), 0) - coalesce(pay.paid_huf, 0), 0)::bigint as remaining_huf,
    case
      when b.stored_status = 'not_payable_adjustment' then 'not_payable_adjustment'::public.payment_status
      when greatest(b.base_due_huf + coalesce(a.adjustment_huf, 0), 0) = 0 then 'not_payable_adjustment'::public.payment_status
      when coalesce(pay.paid_huf, 0) = 0 then 'payable'::public.payment_status
      when coalesce(pay.paid_huf, 0) >= greatest(b.base_due_huf + coalesce(a.adjustment_huf, 0), 0) then 'paid'::public.payment_status
      else 'partially_paid'::public.payment_status
    end,
    b.is_closed,
    b.invoice_requested,
    b.invoice_number,
    pay.last_payment_on
  from base b
  left join lateral (
    select coalesce(sum(sa.amount_huf), 0)::bigint as adjustment_huf
    from public.settlement_adjustments sa
    where sa.settlement_id = b.settlement_id
  ) a on true
  left join lateral (
    select coalesce(sum(py.amount_huf), 0)::bigint as paid_huf, max(py.paid_on) as last_payment_on
    from public.payments py
    where py.settlement_id = b.settlement_id and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id)
  ) pay on true
  order by b.user_name, b.user_id;
end;
$$;
create or replace function public.admin_record_payment(
  p_user_id uuid,
  p_settlement_month date,
  p_amount_huf bigint,
  p_paid_on date,
  p_method public.payment_method,
  p_destination public.money_destination,
  p_admin_note text,
  p_idempotency_key uuid
)
returns table (
  payment_id uuid,
  settlement_id uuid,
  due_huf bigint,
  paid_huf bigint,
  remaining_huf bigint,
  payment_status public.payment_status
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_settlement_id uuid;
  v_due bigint;
  v_paid_before bigint;
  v_paid_after bigint;
  v_payment_id uuid;
  v_status public.payment_status;
  v_closed_revision_id uuid;
  v_adjustment bigint;
  v_existing record;
  v_normalized_note text := nullif(trim(coalesce(p_admin_note, '')), '');
  v_correlation_id uuid := extensions.gen_random_uuid();
begin
  if p_user_id is null or not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;
  if p_amount_huf is null or p_amount_huf <= 0 then
    raise exception 'A befizetés összege csak pozitív lehet.' using errcode = '22023';
  end if;
  if p_paid_on is null then
    raise exception 'A befizetés dátuma kötelező.' using errcode = '22004';
  end if;
  if p_method is null or p_destination is null then
    raise exception 'A fizetési mód és a pénz célhelye kötelező.' using errcode = '22004';
  end if;
  if p_idempotency_key is null then
    raise exception 'Az idempotencia kulcs kötelező.' using errcode = '22004';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text || ':' || p_settlement_month::text, 0));

  insert into public.monthly_settlements (user_id, settlement_month)
  values (p_user_id, p_settlement_month)
  on conflict (user_id, settlement_month) do update set updated_at = now()
  returning id, closed_revision_id into v_settlement_id, v_closed_revision_id;

  select py.id, py.booking_id, py.settlement_id, py.amount_huf, py.paid_on, py.method, py.destination, py.admin_note
    into v_existing
  from public.payments py
  where py.idempotency_key = p_idempotency_key;

  if v_existing.id is not null then
    if v_existing.booking_id is not null or exists(select 1 from public.payment_voids pv where pv.payment_id=v_existing.id) or v_existing.settlement_id <> v_settlement_id
       or v_existing.amount_huf <> p_amount_huf
       or v_existing.paid_on <> p_paid_on
       or v_existing.method <> p_method
       or v_existing.destination <> p_destination
       or v_existing.admin_note is distinct from v_normalized_note then
      raise exception 'Az idempotencia kulcs már egy másik befizetési kéréshez tartozik.' using errcode = 'P0001';
    end if;
    v_payment_id := v_existing.id;
  else
    if v_closed_revision_id is not null then
      select sr.calculated_due_huf into v_due from public.settlement_revisions sr where sr.id = v_closed_revision_id;
    else
      select c.calculated_due_huf into v_due from public.calculate_monthly_pricing(p_user_id, p_settlement_month) c;
    end if;

    select coalesce(sum(sa.amount_huf), 0)::bigint into v_adjustment
    from public.settlement_adjustments sa where sa.settlement_id = v_settlement_id;
    v_due := greatest(coalesce(v_due, 0) + coalesce(v_adjustment, 0), 0);

    select coalesce(sum(py.amount_huf), 0)::bigint into v_paid_before
    from public.payments py where py.settlement_id = v_settlement_id and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id);

    if v_due <= 0 then
      raise exception 'Ehhez a havi elszámoláshoz nincs fizetendő összeg.' using errcode = 'P0001';
    end if;
    if v_paid_before + p_amount_huf > v_due then
      raise exception 'A rögzített befizetés meghaladná a fennmaradó tartozást.' using errcode = 'P0001';
    end if;

    insert into public.payments (
      settlement_id, amount_huf, paid_on, method, destination,
      admin_note, idempotency_key, created_by
    ) values (
      v_settlement_id, p_amount_huf, p_paid_on, p_method, p_destination,
      v_normalized_note, p_idempotency_key, v_actor
    ) returning id into v_payment_id;

    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id,
      before_data, after_data, reason, correlation_id
    ) values (
      v_actor, 'payment.created', 'payment', v_payment_id::text,
      null,
      jsonb_build_object(
        'settlement_id', v_settlement_id,
        'user_id', p_user_id,
        'settlement_month', p_settlement_month,
        'amount_huf', p_amount_huf,
        'paid_on', p_paid_on,
        'method', p_method,
        'destination', p_destination,
        'admin_note', v_normalized_note
      ),
      'Befizetés rögzítése', v_correlation_id
    );
  end if;

  if v_closed_revision_id is not null then
    select sr.calculated_due_huf into v_due from public.settlement_revisions sr where sr.id = v_closed_revision_id;
  else
    select c.calculated_due_huf into v_due from public.calculate_monthly_pricing(p_user_id, p_settlement_month) c;
  end if;
  select coalesce(sum(sa.amount_huf), 0)::bigint into v_adjustment
  from public.settlement_adjustments sa where sa.settlement_id = v_settlement_id;
  v_due := greatest(coalesce(v_due, 0) + coalesce(v_adjustment, 0), 0);

  select coalesce(sum(py.amount_huf), 0)::bigint into v_paid_after
  from public.payments py where py.settlement_id = v_settlement_id and not exists(select 1 from public.payment_voids pv where pv.payment_id=py.id);

  v_status := case
    when v_due = 0 then 'not_payable_adjustment'::public.payment_status
    when v_paid_after = 0 then 'payable'::public.payment_status
    when v_paid_after >= v_due then 'paid'::public.payment_status
    else 'partially_paid'::public.payment_status
  end;

  update public.monthly_settlements
  set status = v_status, updated_at = now()
  where id = v_settlement_id;

  return query select v_payment_id, v_settlement_id, v_due, v_paid_after,
    greatest(v_due - v_paid_after, 0)::bigint, v_status;
end;
$$;

create or replace function public.admin_payment_pricing_summary(p_month date)
returns table(
  user_id uuid,user_name text,email text,booking_count bigint,total_minutes bigint,total_hours numeric,
  normal_minutes integer,special_minutes integer,calculated_due_huf bigint,pricing_breakdown jsonb,
  pricing_state text,revision_id uuid,revision_number integer
)
language plpgsql stable security definer set search_path=''
as $$
declare
  v_month date;
  v_profile record;
  v_revision record;
  v_calc record;
begin
  perform public.require_active_admin();
  if p_month is null then raise exception 'Az elszámolási hónap kötelező.' using errcode='22004'; end if;
  v_month:=date_trunc('month',p_month)::date;
  for v_profile in
    select profile.id,profile.last_name||' '||profile.first_name as name,profile.email
    from public.profiles profile
    where exists(
      select 1 from public.bookings booking
      where booking.user_id=profile.id and booking.status='active'
        and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
        and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date
    ) or exists(
      select 1 from public.monthly_settlements settlement
      join public.settlement_revisions revision on revision.id=settlement.closed_revision_id and settlement.is_closed
      where settlement.user_id=profile.id and settlement.settlement_month=v_month
    )
    order by profile.last_name,profile.first_name,profile.id
  loop
    select revision.id,revision.revision_number,revision.normal_minutes,revision.special_minutes,
           revision.calculated_due_huf,revision.pricing_breakdown
    into v_revision
    from public.monthly_settlements settlement
    join public.settlement_revisions revision on revision.id=settlement.closed_revision_id and settlement.is_closed
    where settlement.user_id=v_profile.id and settlement.settlement_month=v_month
    order by revision.revision_number desc limit 1;
    if found then
      return query select v_profile.id,v_profile.name,v_profile.email,count(line.id),
        coalesce(sum(line.duration_minutes),0)::bigint,
        round(coalesce(sum(line.duration_minutes),0)::numeric/60,2),
        v_revision.normal_minutes,v_revision.special_minutes,v_revision.calculated_due_huf,
        coalesce(v_revision.pricing_breakdown,'[]'::jsonb),
        'snapshot'::text,v_revision.id,v_revision.revision_number
      from public.settlement_booking_lines line where line.settlement_revision_id=v_revision.id;
    else
      select * into v_calc from public.calculate_monthly_pricing(v_profile.id,v_month);
      return query select v_profile.id,v_profile.name,v_profile.email,count(booking.id),
        coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/60),0)::bigint,
        round(coalesce(sum(extract(epoch from (booking.end_at-booking.start_at))/3600),0),2),
        v_calc.normal_minutes,v_calc.special_minutes,v_calc.calculated_due_huf,
        coalesce(v_calc.pricing_breakdown,'[]'::jsonb),
        'live'::text,null::uuid,null::integer
      from public.bookings booking where booking.user_id=v_profile.id and booking.status='active'
        and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
        and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date;
    end if;
  end loop;
end;
$$;
create or replace function public.admin_payment_pricing_details(p_month date,p_user_id uuid default null)
returns table(
  booking_id uuid,user_id uuid,user_name text,booking_date date,room_name text,
  start_time time,end_time time,total_minutes bigint,total_hours numeric,
  rate_source public.applied_rate_source,hourly_rate_huf bigint,amount_huf bigint,
  pricing_state text,revision_number integer
)
language plpgsql stable security definer set search_path=''
as $$
declare v_month date;
begin
  perform public.require_active_admin();
  if p_month is null then raise exception 'Az elszámolási hónap kötelező.' using errcode='22004'; end if;
  v_month:=date_trunc('month',p_month)::date;
  return query
  with latest as (
    select distinct on (settlement.user_id)
      settlement.user_id,revision.id as revision_id,revision.revision_number
    from public.monthly_settlements settlement
    join public.settlement_revisions revision on revision.id=settlement.closed_revision_id and settlement.is_closed
    where settlement.settlement_month=v_month and (p_user_id is null or settlement.user_id=p_user_id)
    order by settlement.user_id,revision.revision_number desc
  ), result as (
    select line.booking_id,profile.id as user_id,profile.last_name||' '||profile.first_name as user_name,
      (line.booking_start_at at time zone 'Europe/Budapest')::date as booking_date,line.room_name,
      (line.booking_start_at at time zone 'Europe/Budapest')::time as start_time,
      (line.booking_end_at at time zone 'Europe/Budapest')::time as end_time,
      line.duration_minutes::bigint as total_minutes,round(line.duration_minutes::numeric/60,2) as total_hours,
      line.rate_source,line.hourly_rate_huf,line.amount_huf,'snapshot'::text as pricing_state,latest.revision_number
    from latest
    join public.profiles profile on profile.id=latest.user_id
    join public.settlement_booking_lines line on line.settlement_revision_id=latest.revision_id
    union all
    select booking.id,profile.id,profile.last_name||' '||profile.first_name,
      (booking.start_at at time zone 'Europe/Budapest')::date,room.name,
      (booking.start_at at time zone 'Europe/Budapest')::time,
      (booking.end_at at time zone 'Europe/Budapest')::time,
      (extract(epoch from (booking.end_at-booking.start_at))/60)::bigint,
      round(extract(epoch from (booking.end_at-booking.start_at))/3600,2),
      rate.rate_source,rate.hourly_rate_huf,
      round(extract(epoch from (booking.end_at-booking.start_at))/60*rate.hourly_rate_huf/60)::bigint,
      'live'::text,null::integer
    from public.bookings booking
    join public.profiles profile on profile.id=booking.user_id
    join public.rooms room on room.id=booking.room_id
    cross join lateral public.resolve_booking_applied_rate(
      booking.id,public.month_normal_minutes(booking.user_id,v_month)
    ) rate
    where booking.status='active' and (p_user_id is null or booking.user_id=p_user_id)
      and (booking.start_at at time zone 'Europe/Budapest')::date>=v_month
      and (booking.start_at at time zone 'Europe/Budapest')::date<(v_month+interval '1 month')::date
      and not exists(select 1 from latest where latest.user_id=booking.user_id)
  )
  select result.* from result order by result.user_name,result.booking_date,result.start_time,result.booking_id;
end;
$$;

revoke all on function public.admin_payment_pricing_summary(date) from public,anon;
revoke all on function public.admin_payment_pricing_details(date,uuid) from public,anon;
grant execute on function public.admin_payment_pricing_summary(date) to authenticated;
grant execute on function public.admin_payment_pricing_details(date,uuid) to authenticated;

commit;
