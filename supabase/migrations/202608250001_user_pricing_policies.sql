begin;

create type public.user_pricing_scheme as enum ('tiered', 'progressive', 'free');

create table public.user_pricing_policies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  pricing_scheme public.user_pricing_scheme not null default 'tiered',
  valid_from date not null,
  valid_to date,
  valid_period daterange generated always as (
    daterange(valid_from, coalesce(valid_to + 1, 'infinity'::date), '[)')
  ) stored,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint user_pricing_policy_dates_valid check (valid_to is null or valid_to >= valid_from),
  constraint user_pricing_policy_month_start check (valid_from = date_trunc('month', valid_from)::date),
  constraint user_pricing_policy_no_overlap exclude using gist (
    user_id with =,
    valid_period with &&
  )
);

create index user_pricing_policies_user_valid_from_idx
  on public.user_pricing_policies(user_id, valid_from desc);

alter table public.user_pricing_policies enable row level security;
revoke all on table public.user_pricing_policies from public, anon, authenticated;

create or replace function public.effective_user_pricing_scheme(
  p_user_id uuid,
  p_on_date date
)
returns public.user_pricing_scheme
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select policy.pricing_scheme
      from public.user_pricing_policies policy
      where policy.user_id = p_user_id
        and p_on_date between policy.valid_from and coalesce(policy.valid_to, 'infinity'::date)
      order by policy.valid_from desc
      limit 1
    ),
    'tiered'::public.user_pricing_scheme
  );
$$;

create or replace function public.admin_list_user_pricing_policies()
returns table (
  id uuid,
  user_id uuid,
  pricing_scheme public.user_pricing_scheme,
  valid_from date,
  valid_to date,
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
    select policy.id, policy.user_id, policy.pricing_scheme, policy.valid_from, policy.valid_to, policy.created_at
    from public.user_pricing_policies policy
    order by policy.user_id, policy.valid_from desc;
end;
$$;

create or replace function public.admin_set_user_pricing_policy(
  p_user_id uuid,
  p_pricing_scheme public.user_pricing_scheme,
  p_valid_from date,
  p_correlation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_existing_id uuid;
  v_covering_id uuid;
  v_next_start date;
  v_new_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_current_month date := date_trunc('month', current_date)::date;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if p_user_id is null or not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if p_pricing_scheme is null then
    raise exception 'A díjazási mód kötelező.' using errcode = '22004';
  end if;
  if p_valid_from is null then
    raise exception 'Az érvényesség kezdete kötelező.' using errcode = '22004';
  end if;
  if p_valid_from <> date_trunc('month', p_valid_from)::date then
    raise exception 'A díjazási mód érvényessége csak hónap első napján kezdődhet.' using errcode = '22023';
  end if;
  if p_valid_from < v_current_month then
    raise exception 'Korábbi lezárt hónap díjazási módja nem módosítható.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('user_pricing_policy:' || p_user_id::text, 0));

  select policy.id, to_jsonb(policy)
    into v_existing_id, v_before
  from public.user_pricing_policies policy
  where policy.user_id = p_user_id and policy.valid_from = p_valid_from
  for update;

  if v_existing_id is not null then
    update public.user_pricing_policies
      set pricing_scheme = p_pricing_scheme
    where id = v_existing_id
      and pricing_scheme is distinct from p_pricing_scheme;
    v_new_id := v_existing_id;
  else
    select policy.id
      into v_covering_id
    from public.user_pricing_policies policy
    where policy.user_id = p_user_id
      and p_valid_from between policy.valid_from and coalesce(policy.valid_to, 'infinity'::date)
    order by policy.valid_from desc
    limit 1
    for update;

    select min(policy.valid_from)
      into v_next_start
    from public.user_pricing_policies policy
    where policy.user_id = p_user_id
      and policy.valid_from > p_valid_from;

    if v_covering_id is not null then
      select to_jsonb(policy) into v_before
      from public.user_pricing_policies policy where policy.id = v_covering_id;
      update public.user_pricing_policies
        set valid_to = p_valid_from - 1
      where id = v_covering_id;
    else
      v_before := jsonb_build_object(
        'pricing_scheme', public.effective_user_pricing_scheme(p_user_id, p_valid_from),
        'implicit_default', true
      );
    end if;

    insert into public.user_pricing_policies (
      user_id, pricing_scheme, valid_from, valid_to, created_by
    ) values (
      p_user_id,
      p_pricing_scheme,
      p_valid_from,
      case when v_next_start is null then null else v_next_start - 1 end,
      v_actor_id
    ) returning id into v_new_id;
  end if;

  select to_jsonb(policy) into v_after
  from public.user_pricing_policies policy where policy.id = v_new_id;

  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id,
      'user_pricing_policy.set',
      'user_pricing_policy',
      p_user_id::text,
      v_before,
      v_after,
      p_correlation_id
    );
  end if;

  return v_new_id;
end;
$$;

revoke execute on function public.effective_user_pricing_scheme(uuid,date) from public, anon, authenticated;
revoke execute on function public.admin_list_user_pricing_policies() from public, anon;
revoke execute on function public.admin_set_user_pricing_policy(uuid,public.user_pricing_scheme,date,uuid) from public, anon;
grant execute on function public.admin_list_user_pricing_policies() to authenticated;
grant execute on function public.admin_set_user_pricing_policy(uuid,public.user_pricing_scheme,date,uuid) to authenticated;

commit;
