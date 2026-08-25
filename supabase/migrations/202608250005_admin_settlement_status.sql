begin;

create or replace function public.admin_monthly_settlement_status(p_month date)
returns table (
  user_id uuid,
  settlement_month date,
  is_closed boolean,
  closed_at timestamptz,
  revision_id uuid,
  revision_number integer,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
  calculated_due_huf bigint,
  calculation_input_hash text
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
    ms.user_id,
    ms.settlement_month,
    ms.is_closed,
    ms.closed_at,
    sr.id,
    sr.revision_number,
    sr.pricing_scheme,
    sr.normal_minutes,
    sr.special_minutes,
    sr.calculated_due_huf,
    sr.calculation_input_hash
  from public.monthly_settlements ms
  left join public.settlement_revisions sr on sr.id = ms.closed_revision_id
  where ms.settlement_month = p_month
  order by ms.user_id;
end;
$$;

revoke execute on function public.admin_monthly_settlement_status(date) from public, anon;
grant execute on function public.admin_monthly_settlement_status(date) to authenticated;

commit;
