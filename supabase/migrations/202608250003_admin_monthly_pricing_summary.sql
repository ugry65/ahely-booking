begin;

revoke execute on function public.calculate_monthly_pricing(uuid,date) from authenticated;
grant execute on function public.calculate_monthly_pricing(uuid,date) to service_role;

create or replace function public.admin_monthly_pricing_summary(
  p_month date
)
returns table (
  user_id uuid,
  user_name text,
  settlement_month date,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
  total_minutes integer,
  normal_due_huf bigint,
  special_due_huf bigint,
  calculated_due_huf bigint,
  pricing_breakdown jsonb,
  calculation_input_hash text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Nincs jogosultság a havi díjazási összesítőhöz.' using errcode = '42501';
  end if;

  if p_month is null or p_month <> date_trunc('month', p_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  return query
  select
    p.id,
    trim(concat_ws(' ', p.last_name, p.first_name))::text,
    calc.settlement_month,
    calc.pricing_scheme,
    calc.normal_minutes,
    calc.special_minutes,
    (calc.normal_minutes + calc.special_minutes)::integer,
    calc.normal_due_huf,
    calc.special_due_huf,
    calc.calculated_due_huf,
    calc.pricing_breakdown,
    calc.calculation_input_hash
  from public.profiles p
  cross join lateral public.calculate_monthly_pricing(p.id, p_month) calc
  where p.is_active
    and calc.normal_minutes + calc.special_minutes > 0
  order by p.last_name, p.first_name, p.id;
end;
$$;

revoke execute on function public.admin_monthly_pricing_summary(date) from public, anon;
grant execute on function public.admin_monthly_pricing_summary(date) to authenticated;

comment on function public.admin_monthly_pricing_summary(date) is
  'Admin-only havi pénzügyi read model. Minden összeget a központi calculate_monthly_pricing motorból vesz át; a UI nem számol önállóan.';

commit;
