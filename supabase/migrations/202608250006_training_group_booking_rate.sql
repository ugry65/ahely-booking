begin;

alter table public.bookings
  add column group_hourly_rate_huf bigint check (group_hourly_rate_huf is null or group_hourly_rate_huf >= 0);

comment on column public.bookings.group_hourly_rate_huf is
  'Tréningterem csoportos használat foglalásonként rögzített óradíja. Default 5000 Ft/óra; admin foglalásonként felülírhatja.';

create or replace function public.apply_training_group_booking_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_training boolean;
begin
  select r.is_training_room into v_is_training
  from public.rooms r
  where r.id = new.room_id;

  if coalesce(v_is_training, false) and new.use_type = 'group' then
    if new.group_hourly_rate_huf is null then
      new.group_hourly_rate_huf := 5000;
    end if;
  else
    new.group_hourly_rate_huf := null;
  end if;
  return new;
end;
$$;

create trigger bookings_training_group_rate_default
before insert or update of room_id, use_type, group_hourly_rate_huf on public.bookings
for each row execute function public.apply_training_group_booking_rate();

update public.bookings b
set group_hourly_rate_huf = 5000
from public.rooms r
where r.id = b.room_id
  and r.is_training_room
  and b.use_type = 'group'
  and b.group_hourly_rate_huf is null;

create or replace function public.admin_set_booking_group_rate(
  p_booking_id uuid,
  p_hourly_rate_huf bigint,
  p_correlation_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_before bigint;
  v_after bigint;
  v_is_training boolean;
  v_use_type public.booking_use_type;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if p_hourly_rate_huf is null or p_hourly_rate_huf < 0 then
    raise exception 'Az óradíj nem lehet negatív.' using errcode = '22023';
  end if;

  select b.group_hourly_rate_huf, r.is_training_room, b.use_type
    into v_before, v_is_training, v_use_type
  from public.bookings b
  join public.rooms r on r.id = b.room_id
  where b.id = p_booking_id
  for update of b;

  if not found then
    raise exception 'A foglalás nem található.' using errcode = 'P0001';
  end if;
  if not v_is_training or v_use_type <> 'group' then
    raise exception 'Egyedi csoportos óradíj csak a Tréningterem csoportos foglalásán állítható.' using errcode = 'P0001';
  end if;

  update public.bookings
  set group_hourly_rate_huf = p_hourly_rate_huf,
      updated_at = clock_timestamp()
  where id = p_booking_id
  returning group_hourly_rate_huf into v_after;

  if v_before is distinct from v_after then
    insert into public.audit_logs(
      actor_user_id, action, entity_type, entity_id,
      before_data, after_data, reason, correlation_id
    ) values (
      v_actor, 'booking.group_rate_changed', 'booking', p_booking_id::text,
      jsonb_build_object('group_hourly_rate_huf', v_before),
      jsonb_build_object('group_hourly_rate_huf', v_after),
      'Tréningterem csoportos foglalás egyedi óradíja', p_correlation_id
    );
  end if;

  return v_after;
end;
$$;

revoke execute on function public.admin_set_booking_group_rate(uuid,bigint,uuid) from public, anon;
grant execute on function public.admin_set_booking_group_rate(uuid,bigint,uuid) to authenticated;
revoke execute on function public.apply_training_group_booking_rate() from public, anon, authenticated;

create or replace function public.calculate_monthly_pricing(
  p_user_id uuid,
  p_settlement_month date
)
returns table (
  user_id uuid,
  settlement_month date,
  pricing_scheme public.user_pricing_scheme,
  normal_minutes integer,
  special_minutes integer,
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
declare
  v_month_start date;
  v_month_end date;
  v_scheme public.user_pricing_scheme;
  v_normal_minutes integer := 0;
  v_special_minutes integer := 0;
  v_normal_due bigint := 0;
  v_special_due bigint := 0;
  v_fixed_rate bigint;
  v_tier record;
  v_remaining integer;
  v_slice integer;
  v_consumed integer := 0;
  v_breakdown jsonb := '[]'::jsonb;
  v_booking_digest text;
  v_special record;
begin
  if p_user_id is null or not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month', p_settlement_month)::date then
    raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode = '22023';
  end if;

  v_month_start := p_settlement_month;
  v_month_end := (p_settlement_month + interval '1 month')::date;
  v_scheme := public.effective_user_pricing_scheme(p_user_id, p_settlement_month);

  select override.hourly_rate_huf into v_fixed_rate
  from public.user_price_overrides override
  where override.user_id = p_user_id
    and p_settlement_month between override.valid_from and coalesce(override.valid_to, 'infinity'::date)
  order by override.valid_from desc limit 1;

  select
    coalesce(sum((extract(epoch from (b.end_at - b.start_at)) / 60)::integer) filter (where not (r.is_training_room and b.use_type = 'group')), 0)::integer,
    coalesce(sum((extract(epoch from (b.end_at - b.start_at)) / 60)::integer) filter (where r.is_training_room and b.use_type = 'group'), 0)::integer,
    md5(coalesce(string_agg(
      b.id::text || ':' || b.updated_at::text || ':' || b.status::text || ':' || b.start_at::text || ':' || b.end_at::text || ':' || b.use_type::text || ':' || coalesce(b.group_hourly_rate_huf::text,''),
      '|' order by b.id
    ), ''))
  into v_normal_minutes, v_special_minutes, v_booking_digest
  from public.bookings b
  join public.rooms r on r.id = b.room_id
  where b.user_id = p_user_id
    and b.status = 'active'
    and (b.start_at at time zone 'Europe/Budapest')::date >= v_month_start
    and (b.start_at at time zone 'Europe/Budapest')::date < v_month_end;

  if v_scheme = 'free' then
    v_breakdown := jsonb_build_array(jsonb_build_object('kind','free','minutes',v_normal_minutes + v_special_minutes,'hourly_rate_huf',0,'amount_huf',0));
  else
    if v_fixed_rate is not null then
      v_normal_due := round(v_normal_minutes::numeric * v_fixed_rate / 60)::bigint;
      if v_normal_minutes > 0 then
        v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object('kind','normal','mode','fixed_user','minutes',v_normal_minutes,'hourly_rate_huf',v_fixed_rate,'amount_huf',v_normal_due));
      end if;
    elsif v_scheme = 'tiered' then
      select t.id, t.min_minutes, t.max_minutes, t.hourly_rate_huf into v_tier
      from public.pricing_tiers t
      where v_normal_minutes between t.min_minutes and coalesce(t.max_minutes, 2147483647)
        and p_settlement_month between t.valid_from and coalesce(t.valid_to, 'infinity'::date)
      order by t.min_minutes desc limit 1;
      if v_normal_minutes > 0 and v_tier.id is null then raise exception 'Nincs érvényes díjsáv a havi óraszámhoz.' using errcode='P0001'; end if;
      if v_normal_minutes > 0 then
        v_normal_due := round(v_normal_minutes::numeric * v_tier.hourly_rate_huf / 60)::bigint;
        v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object('kind','normal','mode','tiered','pricing_rule_id',v_tier.id,'minutes',v_normal_minutes,'hourly_rate_huf',v_tier.hourly_rate_huf,'amount_huf',v_normal_due));
      end if;
    else
      v_remaining := v_normal_minutes; v_consumed := 0;
      for v_tier in select t.id,t.min_minutes,t.max_minutes,t.hourly_rate_huf from public.pricing_tiers t where p_settlement_month between t.valid_from and coalesce(t.valid_to,'infinity'::date) order by t.min_minutes loop
        exit when v_remaining <= 0;
        if v_tier.max_minutes is null then v_slice := v_remaining; else v_slice := least(v_remaining, greatest(v_tier.max_minutes - v_consumed,0)); end if;
        if v_slice > 0 then
          v_normal_due := v_normal_due + round(v_slice::numeric * v_tier.hourly_rate_huf / 60)::bigint;
          v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object('kind','normal','mode','progressive','pricing_rule_id',v_tier.id,'minutes',v_slice,'hourly_rate_huf',v_tier.hourly_rate_huf,'amount_huf',round(v_slice::numeric * v_tier.hourly_rate_huf / 60)::bigint));
          v_remaining := v_remaining - v_slice; v_consumed := v_consumed + v_slice;
        end if;
      end loop;
      if v_remaining > 0 then raise exception 'A progresszív díjsávok nem fedik le a havi óraszámot.' using errcode='P0001'; end if;
    end if;

    for v_special in
      select coalesce(b.group_hourly_rate_huf,5000)::bigint as hourly_rate_huf,
             sum((extract(epoch from (b.end_at-b.start_at))/60)::integer)::integer as minutes
      from public.bookings b join public.rooms r on r.id=b.room_id
      where b.user_id=p_user_id and b.status='active' and r.is_training_room and b.use_type='group'
        and (b.start_at at time zone 'Europe/Budapest')::date >= v_month_start
        and (b.start_at at time zone 'Europe/Budapest')::date < v_month_end
      group by coalesce(b.group_hourly_rate_huf,5000)
      order by coalesce(b.group_hourly_rate_huf,5000)
    loop
      v_special_due := v_special_due + round(v_special.minutes::numeric * v_special.hourly_rate_huf / 60)::bigint;
      v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
        'kind','special_room','mode','booking_rate','minutes',v_special.minutes,
        'hourly_rate_huf',v_special.hourly_rate_huf,
        'amount_huf',round(v_special.minutes::numeric * v_special.hourly_rate_huf / 60)::bigint
      ));
    end loop;
  end if;

  return query select p_user_id,p_settlement_month,v_scheme,v_normal_minutes,v_special_minutes,v_normal_due,v_special_due,v_normal_due+v_special_due,v_breakdown,
    encode(extensions.digest(p_user_id::text || '|' || p_settlement_month::text || '|' || v_scheme::text || '|' || coalesce(v_fixed_rate::text,'') || '|' || v_normal_minutes::text || '|' || v_special_minutes::text || '|' || coalesce(v_booking_digest,'') || '|' || v_breakdown::text,'sha256'),'hex');
end;
$$;

create or replace function public.admin_close_monthly_settlement(
  p_user_id uuid,
  p_settlement_month date
)
returns table (settlement_id uuid, revision_id uuid, revision_number integer, calculated_due_huf bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid; v_current_month date; v_settlement_id uuid; v_is_closed boolean; v_revision_id uuid; v_revision_number integer;
  v_calc record; v_booking record; v_tier record; v_fixed_rate bigint; v_booking_minutes integer; v_remaining integer; v_slice integer;
  v_consumed_normal integer := 0; v_part integer; v_line_total bigint; v_line_minutes integer; v_correlation_id uuid := extensions.gen_random_uuid();
begin
  perform public.require_active_admin(); v_actor := auth.uid();
  if p_user_id is null or not exists(select 1 from public.profiles p where p.id=p_user_id) then raise exception 'A felhasználó nem található.' using errcode='P0001'; end if;
  if p_settlement_month is null or p_settlement_month <> date_trunc('month',p_settlement_month)::date then raise exception 'Az elszámolási hónap első napját kell megadni.' using errcode='22023'; end if;
  v_current_month := date_trunc('month',pg_catalog.timezone('Europe/Budapest',now()))::date;
  if p_settlement_month >= v_current_month then raise exception 'Csak már befejeződött hónap zárható le.' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text || ':' || p_settlement_month::text,0));
  insert into public.monthly_settlements(user_id,settlement_month) values(p_user_id,p_settlement_month)
    on conflict(user_id,settlement_month) do update set updated_at=now() returning id,is_closed into v_settlement_id,v_is_closed;
  if v_is_closed then raise exception 'Ez a havi elszámolás már le van zárva.' using errcode='P0001'; end if;
  select * into v_calc from public.calculate_monthly_pricing(p_user_id,p_settlement_month);
  select coalesce(max(sr.revision_number),0)+1 into v_revision_number from public.settlement_revisions sr where sr.settlement_id=v_settlement_id;
  insert into public.settlement_revisions(settlement_id,revision_number,normal_minutes,special_minutes,calculated_due_huf,calculation_input_hash,calculated_by,pricing_scheme,pricing_breakdown)
  values(v_settlement_id,v_revision_number,v_calc.normal_minutes,v_calc.special_minutes,v_calc.calculated_due_huf,v_calc.calculation_input_hash,v_actor,v_calc.pricing_scheme,v_calc.pricing_breakdown)
  returning id into v_revision_id;
  select override.hourly_rate_huf into v_fixed_rate from public.user_price_overrides override where override.user_id=p_user_id and p_settlement_month between override.valid_from and coalesce(override.valid_to,'infinity'::date) order by override.valid_from desc limit 1;
  if v_calc.normal_minutes>0 and v_calc.pricing_scheme='tiered' and v_fixed_rate is null then
    select t.id,t.min_minutes,t.max_minutes,t.hourly_rate_huf into v_tier from public.pricing_tiers t where v_calc.normal_minutes between t.min_minutes and coalesce(t.max_minutes,2147483647) and p_settlement_month between t.valid_from and coalesce(t.valid_to,'infinity'::date) order by t.min_minutes desc limit 1;
  end if;
  for v_booking in
    select b.id,b.start_at,(extract(epoch from(b.end_at-b.start_at))/60)::integer as duration_minutes,(r.is_training_room and b.use_type='group') as is_special,coalesce(b.group_hourly_rate_huf,5000)::bigint as group_hourly_rate_huf
    from public.bookings b join public.rooms r on r.id=b.room_id
    where b.user_id=p_user_id and b.status='active' and (b.start_at at time zone 'Europe/Budapest')::date>=p_settlement_month and (b.start_at at time zone 'Europe/Budapest')::date<(p_settlement_month+interval '1 month')::date
    order by b.start_at,b.id
  loop
    v_booking_minutes := v_booking.duration_minutes;
    if v_calc.pricing_scheme='free' then
      insert into public.settlement_booking_lines(settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,hourly_rate_huf,amount_huf,line_part_index,pricing_scheme,line_kind)
      values(v_revision_id,v_booking.id,v_booking_minutes,null,null,0,0,1,'free','free');
    elsif v_booking.is_special then
      insert into public.settlement_booking_lines(settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,hourly_rate_huf,amount_huf,line_part_index,pricing_scheme,line_kind)
      values(v_revision_id,v_booking.id,v_booking_minutes,'special_room',null,v_booking.group_hourly_rate_huf,round(v_booking_minutes::numeric*v_booking.group_hourly_rate_huf/60)::bigint,1,v_calc.pricing_scheme,'special_room');
    elsif v_fixed_rate is not null then
      insert into public.settlement_booking_lines(settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,hourly_rate_huf,amount_huf,line_part_index,pricing_scheme,line_kind)
      values(v_revision_id,v_booking.id,v_booking_minutes,'fixed_user',null,v_fixed_rate,round(v_booking_minutes::numeric*v_fixed_rate/60)::bigint,1,v_calc.pricing_scheme,'normal');
    elsif v_calc.pricing_scheme='tiered' then
      if v_tier.id is null then raise exception 'Nincs érvényes díjsáv a snapshothoz.' using errcode='P0001'; end if;
      insert into public.settlement_booking_lines(settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,hourly_rate_huf,amount_huf,line_part_index,pricing_scheme,line_kind)
      values(v_revision_id,v_booking.id,v_booking_minutes,'tiered',v_tier.id,v_tier.hourly_rate_huf,round(v_booking_minutes::numeric*v_tier.hourly_rate_huf/60)::bigint,1,'tiered','normal');
    else
      v_remaining:=v_booking_minutes; v_part:=1;
      while v_remaining>0 loop
        select t.id,t.max_minutes,t.hourly_rate_huf into v_tier from public.pricing_tiers t where p_settlement_month between t.valid_from and coalesce(t.valid_to,'infinity'::date) and (t.max_minutes is null or v_consumed_normal<t.max_minutes) order by t.min_minutes limit 1;
        if v_tier.id is null then raise exception 'A progresszív díjsávok nem fedik le a snapshotot.' using errcode='P0001'; end if;
        if v_tier.max_minutes is null then v_slice:=v_remaining; else v_slice:=least(v_remaining,v_tier.max_minutes-v_consumed_normal); end if;
        if v_slice<=0 then raise exception 'Érvénytelen progresszív díjsáv a snapshotban.' using errcode='P0001'; end if;
        insert into public.settlement_booking_lines(settlement_revision_id,booking_id,duration_minutes,pricing_mode,pricing_rule_id,hourly_rate_huf,amount_huf,line_part_index,pricing_scheme,line_kind)
        values(v_revision_id,v_booking.id,v_slice,'tiered',v_tier.id,v_tier.hourly_rate_huf,round(v_slice::numeric*v_tier.hourly_rate_huf/60)::bigint,v_part,'progressive','normal');
        v_consumed_normal:=v_consumed_normal+v_slice; v_remaining:=v_remaining-v_slice; v_part:=v_part+1;
      end loop;
    end if;
  end loop;
  select coalesce(sum(sbl.amount_huf),0),coalesce(sum(sbl.duration_minutes),0)::integer into v_line_total,v_line_minutes from public.settlement_booking_lines sbl where sbl.settlement_revision_id=v_revision_id;
  if v_line_total<>v_calc.calculated_due_huf then raise exception 'A settlement sorok összege eltér a központi számítástól.' using errcode='P0001'; end if;
  if v_line_minutes<>v_calc.normal_minutes+v_calc.special_minutes then raise exception 'A settlement sorok időtartama eltér a központi számítástól.' using errcode='P0001'; end if;
  update public.monthly_settlements set is_closed=true,closed_at=now(),closed_by=v_actor,closed_revision_id=v_revision_id,updated_at=now() where id=v_settlement_id;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,reason,correlation_id)
  values(v_actor,'monthly_settlement.closed','monthly_settlement',v_settlement_id::text,null,jsonb_build_object('user_id',p_user_id,'settlement_month',p_settlement_month,'revision_id',v_revision_id,'revision_number',v_revision_number,'pricing_scheme',v_calc.pricing_scheme,'normal_minutes',v_calc.normal_minutes,'special_minutes',v_calc.special_minutes,'calculated_due_huf',v_calc.calculated_due_huf,'calculation_input_hash',v_calc.calculation_input_hash),'Havi elszámolás lezárása',v_correlation_id);
  return query select v_settlement_id,v_revision_id,v_revision_number,v_calc.calculated_due_huf;
end;
$$;

commit;
