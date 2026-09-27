begin;

drop function if exists public.admin_monthly_pricing_summary(date);

create or replace function public.admin_monthly_pricing_summary(p_month date)
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
      join public.settlement_revisions revision on revision.settlement_id=settlement.id
      where settlement.user_id=profile.id and settlement.settlement_month=v_month
    )
    order by profile.last_name,profile.first_name,profile.id
  loop
    select revision.id,revision.revision_number,revision.normal_minutes,revision.special_minutes,
           revision.calculated_due_huf,revision.pricing_breakdown
    into v_revision
    from public.monthly_settlements settlement
    join public.settlement_revisions revision on revision.settlement_id=settlement.id
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

revoke execute on function public.admin_monthly_pricing_summary(date) from public,anon;
grant execute on function public.admin_monthly_pricing_summary(date) to authenticated;

commit;
