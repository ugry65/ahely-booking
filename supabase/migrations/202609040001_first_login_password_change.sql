begin;

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

create or replace function public.sync_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is null then
    raise exception 'A-Hely only supports users with an email address' using errcode = '23502';
  end if;

  if tg_op = 'INSERT' then
    insert into public.profiles (
      id, first_name, last_name, email, role, is_active, must_change_password
    ) values (
      new.id,
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''), split_part(lower(new.email), '@', 1)),
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''), ''),
      lower(new.email),
      'user',
      true,
      case when lower(coalesce(new.raw_user_meta_data ->> 'must_change_password', 'false')) = 'true' then true else false end
    );
  elsif new.email is distinct from old.email then
    update public.profiles set email = lower(new.email), updated_at = now() where id = new.id;
  end if;

  return new;
end;
$$;

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
  v_before jsonb;
  v_after jsonb;
begin
  if v_user_id is null then
    raise exception 'Bejelentkezés szükséges.' using errcode = '42501';
  end if;
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  select to_jsonb(profile) into v_before
  from public.profiles profile
  where profile.id = v_user_id and profile.is_active
  for update;
  if v_before is null then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;

  update public.profiles
  set must_change_password = false, updated_at = now()
  where id = v_user_id;

  select to_jsonb(profile) into v_after from public.profiles profile where profile.id = v_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_user_id, 'profile.initial_password_changed', 'profile', v_user_id::text,
      jsonb_build_object('must_change_password', v_before -> 'must_change_password'),
      jsonb_build_object('must_change_password', v_after -> 'must_change_password'),
      p_correlation_id
    );
  end if;
end;
$$;

revoke execute on function public.complete_own_password_change(uuid) from public, anon;
grant execute on function public.complete_own_password_change(uuid) to authenticated;
grant select (must_change_password) on public.profiles to authenticated;

comment on column public.profiles.must_change_password is
  'Az admin által létrehozott kezdőjelszó után az első belépéskor kötelező jelszócsere jelzője; a jelszó maga nem tárolódik itt.';
comment on function public.complete_own_password_change(uuid) is
  'A bejelentkezett user sikeres első jelszócseréjének auditált lezárása; jelszót nem fogad és nem tárol.';

commit;
