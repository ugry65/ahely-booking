begin;

alter table public.profiles
  add column if not exists billing_name text,
  add column if not exists onboarding_completed_at timestamptz;

create or replace function public.complete_own_onboarding(
  p_phone text,
  p_customer_type text,
  p_billing_name text,
  p_billing_postal_code text,
  p_billing_city text,
  p_billing_street text,
  p_billing_house_number text,
  p_tax_number text,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_customer_type text := lower(btrim(coalesce(p_customer_type, '')));
  v_before jsonb;
  v_after jsonb;
begin
  if v_actor_id is null then
    raise exception 'Bejelentkezés szükséges.' using errcode = '42501';
  end if;
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_actor_id and is_active
  for update;

  if not found then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501';
  end if;
  if v_customer_type not in ('private', 'business') then
    raise exception 'Válaszd ki, hogy magánszemélyként vagy vállalkozóként kéred a számlát.' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_phone, '')), '') is null then
    raise exception 'A telefonszám megadása kötelező.' using errcode = 'P0001';
  end if;
  if nullif(btrim(coalesce(p_billing_name, '')), '') is null then
    raise exception 'A számlázási név megadása kötelező.' using errcode = 'P0001';
  end if;
  if nullif(btrim(coalesce(p_billing_postal_code, '')), '') is null
    or nullif(btrim(coalesce(p_billing_city, '')), '') is null
    or nullif(btrim(coalesce(p_billing_street, '')), '') is null
    or nullif(btrim(coalesce(p_billing_house_number, '')), '') is null then
    raise exception 'A teljes számlázási cím megadása kötelező.' using errcode = 'P0001';
  end if;
  if v_customer_type = 'business' and nullif(btrim(coalesce(p_tax_number, '')), '') is null then
    raise exception 'Vállalkozói számlázás esetén az adószám megadása kötelező.' using errcode = 'P0001';
  end if;

  v_before := jsonb_build_object(
    'phone', v_profile.phone,
    'customer_type', v_profile.customer_type,
    'billing_name', v_profile.billing_name,
    'billing_postal_code', v_profile.billing_postal_code,
    'billing_city', v_profile.billing_city,
    'billing_street', v_profile.billing_street,
    'billing_house_number', v_profile.billing_house_number,
    'tax_number', v_profile.tax_number,
    'onboarding_completed_at', v_profile.onboarding_completed_at
  );

  update public.profiles
  set phone = btrim(p_phone),
      customer_type = v_customer_type,
      billing_name = btrim(p_billing_name),
      billing_postal_code = btrim(p_billing_postal_code),
      billing_city = btrim(p_billing_city),
      billing_street = btrim(p_billing_street),
      billing_house_number = btrim(p_billing_house_number),
      tax_number = case when v_customer_type = 'business' then btrim(p_tax_number) else null end,
      onboarding_completed_at = coalesce(onboarding_completed_at, now()),
      updated_at = now()
  where id = v_actor_id;

  select jsonb_build_object(
    'phone', profile.phone,
    'customer_type', profile.customer_type,
    'billing_name', profile.billing_name,
    'billing_postal_code', profile.billing_postal_code,
    'billing_city', profile.billing_city,
    'billing_street', profile.billing_street,
    'billing_house_number', profile.billing_house_number,
    'tax_number', profile.tax_number,
    'onboarding_completed_at', profile.onboarding_completed_at
  ) into v_after
  from public.profiles profile where profile.id = v_actor_id;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id,
    before_data, after_data, correlation_id
  ) values (
    v_actor_id, 'profile.onboarding.completed', 'profile', v_actor_id::text,
    v_before, v_after, p_correlation_id
  );
end;
$$;

revoke execute on function public.complete_own_onboarding(text,text,text,text,text,text,text,text,uuid) from public, anon;
grant execute on function public.complete_own_onboarding(text,text,text,text,text,text,text,text,uuid) to authenticated;

grant select (billing_name, onboarding_completed_at) on public.profiles to authenticated;

comment on column public.profiles.billing_name is
  'A számlán megjelenő név; eltérhet a felhasználó vezeték- és keresztnevétől.';
comment on column public.profiles.onboarding_completed_at is
  'Az első kötelező profil- és számlázásiadat-kitöltés sikeres lezárásának időpontja.';
comment on function public.complete_own_onboarding(text,text,text,text,text,text,text,text,uuid) is
  'Aktív user saját kötelező első belépési adatainak mentése; teljes cím és telefonszám kötelező, vállalkozói számlázásnál adószám is.';

commit;
