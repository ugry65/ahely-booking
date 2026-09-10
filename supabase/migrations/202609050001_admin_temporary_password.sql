begin;

create or replace function public.admin_require_password_change(
  p_user_id uuid,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before boolean;
  v_active boolean;
begin
  if p_user_id is null then
    raise exception 'A felhasználói azonosító kötelező.' using errcode = '22004';
  end if;
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  select must_change_password, is_active
  into v_before, v_active
  from public.profiles
  where id = p_user_id
  for update;

  if v_before is null then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if not v_active then
    raise exception 'Inaktív felhasználónak nem állítható be ideiglenes jelszó.' using errcode = 'P0001';
  end if;

  update public.profiles
  set must_change_password = true,
      updated_at = now()
  where id = p_user_id;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
  ) values (
    v_actor_id,
    'profile.temporary_password_required',
    'profile',
    p_user_id::text,
    jsonb_build_object('must_change_password', v_before),
    jsonb_build_object('must_change_password', true),
    p_correlation_id
  );
end;
$$;

revoke execute on function public.admin_require_password_change(uuid, uuid) from public, anon;
grant execute on function public.admin_require_password_change(uuid, uuid) to authenticated;

comment on function public.admin_require_password_change(uuid, uuid) is
  'Aktív admin ideiglenesjelszó-beállításának előkészítése: kötelező következő jelszócserét állít és auditál, jelszót nem fogad vagy tárol.';

commit;
