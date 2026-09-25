begin;

create or replace function public.admin_list_user_price_overrides()
returns table (
  id uuid,
  user_id uuid,
  hourly_rate_huf bigint,
  valid_from date,
  valid_to date,
  reason text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.require_active_admin();
  return query
    select o.id, o.user_id, o.hourly_rate_huf, o.valid_from, o.valid_to, o.reason, o.created_at
    from public.user_price_overrides o
    order by o.user_id, o.valid_from desc;
end;
$$;

create or replace function public.admin_set_user_pricing_configuration(
  p_user_id uuid,
  p_pricing_mode text,
  p_hourly_rate_huf bigint,
  p_valid_from date,
  p_correlation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_current_month date := date_trunc('month', current_date)::date;
  v_existing_override public.user_price_overrides%rowtype;
  v_covering_override public.user_price_overrides%rowtype;
  v_next_override_start date;
  v_override_id uuid;
  v_before_override jsonb;
  v_after_override jsonb;
  v_policy_id uuid;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_pricing_mode is null or p_pricing_mode not in ('tiered', 'progressive', 'fixed', 'free') then
    raise exception 'Érvénytelen díjazási mód.' using errcode = '22023';
  end if;
  if p_valid_from is null then
    raise exception 'Az érvényesség kezdete kötelező.' using errcode = '22004';
  end if;
  if p_valid_from <> date_trunc('month', p_valid_from)::date then
    raise exception 'A díjazás érvényessége csak hónap első napján kezdődhet.' using errcode = '22023';
  end if;
  if p_valid_from < v_current_month then
    raise exception 'Korábbi lezárt hónap díjazása nem módosítható.' using errcode = '22023';
  end if;
  if p_pricing_mode = 'fixed' and (p_hourly_rate_huf is null or p_hourly_rate_huf < 0) then
    raise exception 'Fix díjazásnál érvényes, nem negatív óradíj kötelező.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('user_pricing_configuration:' || p_user_id::text, 0));

  if p_pricing_mode = 'fixed' then
    -- A DB pricing engineben a Free policy mindent felülír. Fix mód választásakor
    -- ezért explicit nem-Free alappolicyt állítunk ugyanattól a hónaptól.
    v_policy_id := public.admin_set_user_pricing_policy(
      p_user_id,
      'tiered'::public.user_pricing_scheme,
      p_valid_from,
      p_correlation_id
    );

    select o.* into v_existing_override
    from public.user_price_overrides o
    where o.user_id = p_user_id and o.valid_from = p_valid_from
    for update;

    if v_existing_override.id is not null then
      v_before_override := to_jsonb(v_existing_override);
      update public.user_price_overrides
        set hourly_rate_huf = p_hourly_rate_huf,
            reason = 'Admin által beállított Fix óradíj'
      where id = v_existing_override.id;
      v_override_id := v_existing_override.id;
    else
      select o.* into v_covering_override
      from public.user_price_overrides o
      where o.user_id = p_user_id
        and p_valid_from between o.valid_from and coalesce(o.valid_to, 'infinity'::date)
      order by o.valid_from desc
      limit 1
      for update;

      select min(o.valid_from) into v_next_override_start
      from public.user_price_overrides o
      where o.user_id = p_user_id and o.valid_from > p_valid_from;

      if v_covering_override.id is not null then
        v_before_override := to_jsonb(v_covering_override);
        update public.user_price_overrides
          set valid_to = p_valid_from - 1
        where id = v_covering_override.id;
      end if;

      insert into public.user_price_overrides (
        user_id, hourly_rate_huf, valid_from, valid_to, reason, created_by
      ) values (
        p_user_id,
        p_hourly_rate_huf,
        p_valid_from,
        case when v_next_override_start is null then null else v_next_override_start - 1 end,
        'Admin által beállított Fix óradíj',
        v_actor_id
      ) returning id into v_override_id;
    end if;

    select to_jsonb(o) into v_after_override
    from public.user_price_overrides o where o.id = v_override_id;

    if v_before_override is distinct from v_after_override then
      insert into public.audit_logs (
        actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
      ) values (
        v_actor_id,
        'user_price_override.set',
        'user_price_override',
        p_user_id::text,
        v_before_override,
        v_after_override,
        p_correlation_id
      );
    end if;
  else
    v_policy_id := public.admin_set_user_pricing_policy(
      p_user_id,
      p_pricing_mode::public.user_pricing_scheme,
      p_valid_from,
      p_correlation_id
    );

    -- Ha ettől a hónaptól nem Fix a mód, az ezen a napon induló fix tervet töröljük
    -- (audit megtartja az előzményt), a korábban indult effektív fix időszakot pedig lezárjuk.
    select o.* into v_existing_override
    from public.user_price_overrides o
    where o.user_id = p_user_id and o.valid_from = p_valid_from
    for update;

    if v_existing_override.id is not null then
      v_before_override := to_jsonb(v_existing_override);
      delete from public.user_price_overrides where id = v_existing_override.id;
      insert into public.audit_logs (
        actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
      ) values (
        v_actor_id,
        'user_price_override.remove_future',
        'user_price_override',
        p_user_id::text,
        v_before_override,
        null,
        p_correlation_id
      );
    else
      select o.* into v_covering_override
      from public.user_price_overrides o
      where o.user_id = p_user_id
        and o.valid_from < p_valid_from
        and p_valid_from between o.valid_from and coalesce(o.valid_to, 'infinity'::date)
      order by o.valid_from desc
      limit 1
      for update;

      if v_covering_override.id is not null then
        v_before_override := to_jsonb(v_covering_override);
        update public.user_price_overrides
          set valid_to = p_valid_from - 1
        where id = v_covering_override.id;
        select to_jsonb(o) into v_after_override
        from public.user_price_overrides o where o.id = v_covering_override.id;
        insert into public.audit_logs (
          actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
        ) values (
          v_actor_id,
          'user_price_override.close',
          'user_price_override',
          p_user_id::text,
          v_before_override,
          v_after_override,
          p_correlation_id
        );
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'user_id', p_user_id,
    'pricing_mode', p_pricing_mode,
    'hourly_rate_huf', case when p_pricing_mode = 'fixed' then p_hourly_rate_huf else null end,
    'valid_from', p_valid_from,
    'policy_id', v_policy_id,
    'override_id', case when p_pricing_mode = 'fixed' then v_override_id else null end
  );
end;
$$;

revoke execute on function public.admin_list_user_price_overrides() from public, anon;
revoke execute on function public.admin_set_user_pricing_configuration(uuid,text,bigint,date,uuid) from public, anon;
grant execute on function public.admin_list_user_price_overrides() to authenticated;
grant execute on function public.admin_set_user_pricing_configuration(uuid,text,bigint,date,uuid) to authenticated;

commit;
