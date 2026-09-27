begin;
create or replace function public.admin_cleanup_failed_allbooked_auth_profile(
  p_actor_id uuid,
  p_user_id uuid,
  p_expected_email text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id=p_actor_id and role='admin' and is_active) then
    raise exception 'A migrációs takarítást csak aktív admin futtathatja.' using errcode='42501';
  end if;
  if p_user_id is null or nullif(lower(trim(p_expected_email)),'') is null then
    raise exception 'A takarítás user azonosítója és e-mail címe kötelező.' using errcode='22004';
  end if;
  if not exists (select 1 from auth.users where id=p_user_id and lower(email)=lower(trim(p_expected_email))) then
    raise exception 'Az Auth-user azonossága nem bizonyítható.' using errcode='P0001';
  end if;
  if not exists (select 1 from public.profiles where id=p_user_id and lower(email)=lower(trim(p_expected_email)) and role='user') then
    raise exception 'A profil azonossága nem bizonyítható.' using errcode='P0001';
  end if;
  if exists (select 1 from public.bookings where user_id=p_user_id or created_by=p_user_id or hourly_rate_override_set_by=p_user_id)
     or exists (select 1 from public.allbooked_migration_bookings where user_id=p_user_id or imported_by=p_user_id)
     or exists (select 1 from public.access_group_members where user_id=p_user_id)
     or exists (select 1 from public.user_room_permissions where user_id=p_user_id)
     or exists (select 1 from public.user_price_overrides where user_id=p_user_id or created_by=p_user_id)
     or exists (select 1 from public.user_pricing_policies where user_id=p_user_id or created_by=p_user_id)
     or exists (select 1 from public.monthly_settlements where user_id=p_user_id or closed_by=p_user_id)
     or exists (select 1 from public.booking_series where owner_user_id=p_user_id or created_by=p_user_id)
     or exists (select 1 from public.booking_email_outbox where recipient_user_id=p_user_id or actor_user_id=p_user_id)
     or exists (select 1 from public.booking_cancellations where cancelled_by=p_user_id)
     or exists (select 1 from public.booking_operation_requests where actor_user_id=p_user_id)
     or exists (select 1 from public.booking_scope_operations where actor_user_id=p_user_id)
     or exists (select 1 from public.booking_title_requests where actor_user_id=p_user_id)
     or exists (select 1 from public.app_settings where updated_by=p_user_id)
     or exists (select 1 from public.export_runs where created_by=p_user_id)
     or exists (select 1 from public.payments where created_by=p_user_id)
     or exists (select 1 from public.pricing_tiers where created_by=p_user_id)
     or exists (select 1 from public.retention_candidates where approved_by=p_user_id)
     or exists (select 1 from public.settlement_adjustments where created_by=p_user_id)
     or exists (select 1 from public.settlement_revisions where calculated_by=p_user_id)
     or exists (select 1 from public.special_room_rates where created_by=p_user_id)
     or exists (select 1 from public.audit_logs where actor_user_id=p_user_id) then
    raise exception 'A frissen létrehozott profilhoz üzleti adat kapcsolódik; automatikus takarítás tiltva.' using errcode='P0001';
  end if;
  delete from public.profiles where id=p_user_id;
  return found;
end;
$$;
revoke all on function public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text) to service_role;
comment on function public.admin_cleanup_failed_allbooked_auth_profile(uuid,uuid,text) is 'Fail-closed cleanup of an Auth-trigger-created profile after a failed AllBooked import. Removes only a proven business-data-free profile so Auth deletion can follow.';
commit;