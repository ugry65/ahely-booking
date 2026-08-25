begin;

create or replace function public.admin_set_advance_booking_limits(
  p_default_days integer,
  p_training_days integer,
  p_correlation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := public.require_active_admin();
  v_before_default jsonb;
  v_before_training jsonb;
  v_after_default jsonb;
  v_after_training jsonb;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if p_default_days is null or p_training_days is null or p_default_days < 0 or p_training_days < 0 then
    raise exception 'Az előrefoglalási limitek csak nemnegatív egész napértékek lehetnek.' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('advance_booking_limits', 0));

  select value into v_before_default from public.app_settings where key = 'default_advance_booking_days' for update;
  select value into v_before_training from public.app_settings where key = 'training_room_advance_days' for update;

  if v_before_default is null or v_before_training is null then
    raise exception 'Az előrefoglalási beállítások hiányoznak.' using errcode = 'P0001';
  end if;

  update public.app_settings
  set value = to_jsonb(p_default_days), updated_by = v_actor_id, updated_at = now()
  where key = 'default_advance_booking_days';

  update public.app_settings
  set value = to_jsonb(p_training_days), updated_by = v_actor_id, updated_at = now()
  where key = 'training_room_advance_days';

  select value into v_after_default from public.app_settings where key = 'default_advance_booking_days';
  select value into v_after_training from public.app_settings where key = 'training_room_advance_days';

  if v_before_default is distinct from v_after_default or v_before_training is distinct from v_after_training then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id,
      'settings.advance_booking_limits.updated',
      'app_setting',
      'advance_booking_limits',
      jsonb_build_object('default_advance_booking_days', v_before_default, 'training_room_advance_days', v_before_training),
      jsonb_build_object('default_advance_booking_days', v_after_default, 'training_room_advance_days', v_after_training),
      p_correlation_id
    );
  end if;
end;
$$;

revoke all on function public.admin_set_advance_booking_limits(integer,integer,uuid) from public, anon;
grant execute on function public.admin_set_advance_booking_limits(integer,integer,uuid) to authenticated;

comment on function public.admin_set_advance_booking_limits(integer,integer,uuid) is
  'Auditált adminbeállítás a normál és Tréningterem előrefoglalási limitekhez.';

commit;
