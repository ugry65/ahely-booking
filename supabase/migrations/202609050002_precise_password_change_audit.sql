begin;

create or replace function public.complete_own_password_change(
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_must_change_password boolean;
begin
  if v_user_id is null then
    raise exception 'Bejelentkezés szükséges.' using errcode = '42501';
  end if;
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  select must_change_password
  into v_must_change_password
  from public.profiles
  where id = v_user_id and is_active
  for update;

  if v_must_change_password is null then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  -- Normál jelszó-visszaállításkor nincs első belépési állapot, ezért itt
  -- sem profilt, sem "initial_password_changed" auditbejegyzést nem módosítunk.
  if not v_must_change_password then
    return;
  end if;

  update public.profiles
  set must_change_password = false,
      updated_at = now()
  where id = v_user_id;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
  ) values (
    v_user_id,
    'profile.initial_password_changed',
    'profile',
    v_user_id::text,
    jsonb_build_object('must_change_password', true),
    jsonb_build_object('must_change_password', false),
    p_correlation_id
  );
end;
$$;

revoke execute on function public.complete_own_password_change(uuid) from public, anon;
grant execute on function public.complete_own_password_change(uuid) to authenticated;

comment on function public.complete_own_password_change(uuid) is
  'A bejelentkezett user kötelező első/ideiglenes jelszócseréjének auditált lezárása. Normál recovery jelszócserénél no-op; jelszót nem fogad és nem tárol.';

commit;
