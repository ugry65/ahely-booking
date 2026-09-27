begin;

create or replace function public.admin_finalize_user_email_change(
  p_user_id uuid, p_old_email text, p_new_email text, p_reason text, p_correlation_id uuid
) returns void
language plpgsql security definer set search_path=''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_profile_email text;
  v_auth_email text;
  v_new_email text := lower(btrim(coalesce(p_new_email,'')));
  v_old_email text := lower(btrim(coalesce(p_old_email,'')));
begin
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode='22004'; end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'Az indok kötelező.' using errcode='22023'; end if;
  select lower(email) into v_profile_email from public.profiles where id=p_user_id for update;
  select lower(email) into v_auth_email from auth.users where id=p_user_id;
  if v_profile_email is null or v_auth_email is null then raise exception 'A felhasználó nem található.' using errcode='P0001'; end if;
  if v_profile_email not in (v_old_email,v_new_email) then raise exception 'A profil e-mail-címe időközben megváltozott.' using errcode='P0001'; end if;
  if v_auth_email <> v_new_email then raise exception 'Az Auth e-mail-cím nem egyezik az új címmel.' using errcode='P0001'; end if;
  if exists(select 1 from public.profiles where lower(email)=v_new_email and id<>p_user_id) then raise exception 'Ez az e-mail-cím már használatban van.' using errcode='P0001'; end if;

  update public.profiles set email=v_new_email, updated_at=now() where id=p_user_id and lower(email)<>v_new_email;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,before_data,after_data,correlation_id)
  values(v_actor_id,'profile.email_changed','profile',p_user_id::text,
    jsonb_build_object('email',v_old_email,'reason',btrim(p_reason)),
    jsonb_build_object('email',v_new_email,'reason',btrim(p_reason)),p_correlation_id);
end;
$$;

revoke execute on function public.admin_finalize_user_email_change(uuid,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.admin_finalize_user_email_change(uuid,text,text,text,uuid) to service_role;

commit;
