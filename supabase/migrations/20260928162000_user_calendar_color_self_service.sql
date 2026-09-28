create or replace function public.update_own_calendar_color(
  p_calendar_color text,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_color text := upper(btrim(coalesce(p_calendar_color, '')));
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  if v_color not in (
    '#F4B6C2','#E887A5','#F5B895','#EE8B7A','#C5B3E6',
    '#A991D4','#9273C5','#A9D6E5','#83C5E5','#719AC1',
    '#70C7C2','#9DD9C5','#A8C5A0','#A8D080','#C1D99B',
    '#F2D98D','#E9BE67','#D9BE9C','#C9876B','#9AAFC1'
  ) then
    raise exception 'Érvénytelen naptárszín.' using errcode = '22023';
  end if;

  select * into v_actor
  from public.profiles
  where id = auth.uid() and is_active
  for update;

  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  v_before := to_jsonb(v_actor);

  update public.profiles
  set calendar_color = v_color, updated_at = clock_timestamp()
  where id = v_actor.id;

  select to_jsonb(profile) into v_after
  from public.profiles profile
  where profile.id = v_actor.id;

  if v_before is distinct from v_after then
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values(v_actor.id, 'profile.calendar_color_updated', 'profile', v_actor.id::text, v_before, v_after, p_correlation_id);
  end if;
end;
$$;

revoke all on function public.update_own_calendar_color(text, uuid) from public;
grant execute on function public.update_own_calendar_color(text, uuid) to authenticated;
