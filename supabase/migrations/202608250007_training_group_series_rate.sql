begin;

create or replace function public.admin_set_booking_series_group_rate(
  p_series_id uuid,
  p_hourly_rate_huf bigint,
  p_correlation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := public.require_active_admin();
  v_count integer;
  v_invalid_count integer;
begin
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if p_hourly_rate_huf is null or p_hourly_rate_huf < 0 then
    raise exception 'Az óradíj nem lehet negatív.' using errcode = '22023';
  end if;

  if not exists (select 1 from public.booking_series s where s.id = p_series_id) then
    raise exception 'A foglalási sorozat nem található.' using errcode = 'P0001';
  end if;

  select count(*) into v_invalid_count
  from public.bookings b
  join public.rooms r on r.id = b.room_id
  where b.series_id = p_series_id
    and b.status = 'active'
    and (not r.is_training_room or b.use_type <> 'group');

  if v_invalid_count > 0 then
    raise exception 'Egyedi csoportos óradíj csak teljes egészében Tréningterem csoportos sorozatra állítható.' using errcode = 'P0001';
  end if;

  update public.bookings
  set group_hourly_rate_huf = p_hourly_rate_huf,
      updated_at = clock_timestamp()
  where series_id = p_series_id
    and status = 'active'
    and group_hourly_rate_huf is distinct from p_hourly_rate_huf;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    insert into public.audit_logs(
      actor_user_id, action, entity_type, entity_id,
      before_data, after_data, reason, correlation_id
    ) values (
      v_actor, 'booking_series.group_rate_changed', 'booking_series', p_series_id::text,
      null,
      jsonb_build_object('group_hourly_rate_huf', p_hourly_rate_huf, 'affected_bookings', v_count),
      'Tréningterem csoportos foglalási sorozat egyedi óradíja', p_correlation_id
    );
  end if;

  return v_count;
end;
$$;

revoke execute on function public.admin_set_booking_series_group_rate(uuid,bigint,uuid) from public, anon;
grant execute on function public.admin_set_booking_series_group_rate(uuid,bigint,uuid) to authenticated;

commit;
