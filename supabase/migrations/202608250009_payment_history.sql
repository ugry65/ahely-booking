begin;

create or replace function public.admin_payment_history(p_month date)
returns table (
  payment_id uuid,
  user_id uuid,
  user_name text,
  settlement_month date,
  amount_huf bigint,
  paid_on date,
  method public.payment_method,
  destination public.money_destination,
  admin_note text,
  created_at timestamptz,
  created_by_name text
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
  select
    py.id,
    ms.user_id,
    trim(concat_ws(' ', p.last_name, p.first_name))::text,
    ms.settlement_month,
    py.amount_huf,
    py.paid_on,
    py.method,
    py.destination,
    py.admin_note,
    py.created_at,
    trim(concat_ws(' ', actor.last_name, actor.first_name))::text
  from public.payments py
  join public.monthly_settlements ms on ms.id = py.settlement_id
  join public.profiles p on p.id = ms.user_id
  join public.profiles actor on actor.id = py.created_by
  where ms.settlement_month = p_month
  order by py.paid_on desc, py.created_at desc, py.id;
end;
$$;

revoke execute on function public.admin_payment_history(date) from public, anon;
grant execute on function public.admin_payment_history(date) to authenticated;

commit;
