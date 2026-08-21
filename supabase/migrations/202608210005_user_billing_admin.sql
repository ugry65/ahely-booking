begin;

alter table public.profiles
  add column if not exists customer_type text not null default 'private',
  add column if not exists billing_postal_code text,
  add column if not exists billing_city text,
  add column if not exists billing_street text,
  add column if not exists billing_house_number text,
  add column if not exists tax_number text;

alter table public.profiles
  drop constraint if exists profiles_customer_type_valid,
  add constraint profiles_customer_type_valid
    check (customer_type in ('private', 'business')),
  drop constraint if exists profiles_business_tax_number_required,
  add constraint profiles_business_tax_number_required
    check (customer_type <> 'business' or nullif(btrim(tax_number), '') is not null);

create or replace function public.admin_update_profile(
  p_user_id uuid,
  p_first_name text,
  p_last_name text,
  p_phone text,
  p_customer_type text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_street text,
  p_billing_house_number text,
  p_tax_number text,
  p_is_active boolean,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before jsonb;
  v_after jsonb;
  v_customer_type text := lower(btrim(coalesce(p_customer_type, 'private')));
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if nullif(btrim(p_first_name), '') is null or nullif(btrim(p_last_name), '') is null then
    raise exception 'A vezetéknév és a keresztnév kötelező.' using errcode = '22023';
  end if;
  if v_customer_type not in ('private', 'business') then
    raise exception 'Érvénytelen ügyféltípus.' using errcode = '22023';
  end if;
  if v_customer_type = 'business' and nullif(btrim(coalesce(p_tax_number, '')), '') is null then
    raise exception 'Vállalkozó esetén az adószám megadása kötelező.' using errcode = 'P0001';
  end if;

  select to_jsonb(profile) into v_before
  from public.profiles profile
  where profile.id = p_user_id
  for update;

  if v_before is null then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;

  update public.profiles
  set first_name = btrim(p_first_name),
      last_name = btrim(p_last_name),
      phone = nullif(btrim(coalesce(p_phone, '')), ''),
      customer_type = v_customer_type,
      billing_postal_code = nullif(btrim(coalesce(p_billing_postal_code, '')), ''),
      billing_city = nullif(btrim(coalesce(p_billing_city, '')), ''),
      billing_street = nullif(btrim(coalesce(p_billing_street, '')), ''),
      billing_house_number = nullif(btrim(coalesce(p_billing_house_number, '')), ''),
      tax_number = case when v_customer_type = 'business' then nullif(btrim(coalesce(p_tax_number, '')), '') else nullif(btrim(coalesce(p_tax_number, '')), '') end,
      is_active = coalesce(p_is_active, false),
      updated_at = now()
  where id = p_user_id;

  select to_jsonb(profile) into v_after from public.profiles profile where profile.id = p_user_id;
  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id, 'profile.updated', 'profile', p_user_id::text, v_before, v_after, p_correlation_id
    );
  end if;
end;
$$;

create or replace function public.admin_audit_password_reset_request(
  p_user_id uuid,
  p_correlation_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_email text;
  v_active boolean;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  select email, is_active into v_email, v_active
  from public.profiles
  where id = p_user_id;

  if v_email is null then
    raise exception 'A felhasználó nem található.' using errcode = 'P0001';
  end if;
  if not v_active then
    raise exception 'Inaktív felhasználónak nem küldhető jelszó-visszaállító link.' using errcode = 'P0001';
  end if;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
  ) values (
    v_actor_id, 'profile.password_reset_requested', 'profile', p_user_id::text,
    null, jsonb_build_object('email', v_email), p_correlation_id
  );

  return v_email;
end;
$$;

revoke execute on function public.admin_update_profile(uuid, text, text, text, text, text, text, text, text, text, boolean, uuid) from public, anon;
grant execute on function public.admin_update_profile(uuid, text, text, text, text, text, text, text, text, text, boolean, uuid) to authenticated;

revoke execute on function public.admin_audit_password_reset_request(uuid, uuid) from public, anon;
grant execute on function public.admin_audit_password_reset_request(uuid, uuid) to authenticated;

grant select (
  customer_type, billing_postal_code, billing_city, billing_street, billing_house_number, tax_number
) on public.profiles to authenticated;

comment on function public.admin_update_profile(uuid, text, text, text, text, text, text, text, text, text, boolean, uuid) is
  'Admin által szerkeszthető felhasználói törzs- és számlázási adatok, auditáltan.';
comment on function public.admin_audit_password_reset_request(uuid, uuid) is
  'Aktív user jelszó-reset kérésének admin jogosultság-ellenőrzése és auditja; tokent/jelszót nem tárol.';

commit;
