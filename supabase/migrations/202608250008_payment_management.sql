begin;

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
        else coalesce(l.calculated_due_huf, 0)
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
    where py.settlement_id = b.settlement_id
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

  if exists (select 1 from public.payments py where py.idempotency_key = p_idempotency_key) then
    select py.id into v_payment_id from public.payments py where py.idempotency_key = p_idempotency_key;
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
    from public.payments py where py.settlement_id = v_settlement_id;

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
      nullif(trim(coalesce(p_admin_note, '')), ''), p_idempotency_key, v_actor
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
        'admin_note', nullif(trim(coalesce(p_admin_note, '')), '')
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
  from public.payments py where py.settlement_id = v_settlement_id;

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

revoke execute on function public.admin_monthly_payment_summary(date) from public, anon;
revoke execute on function public.admin_record_payment(uuid,date,bigint,date,public.payment_method,public.money_destination,text,uuid) from public, anon;
grant execute on function public.admin_monthly_payment_summary(date) to authenticated;
grant execute on function public.admin_record_payment(uuid,date,bigint,date,public.payment_method,public.money_destination,text,uuid) to authenticated;

commit;
