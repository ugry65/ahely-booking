begin;

insert into public.app_settings (key, value, description)
values ('show_other_booker_names', 'true'::jsonb, 'Más foglalók neve látható-e a normál felhasználók számára.')
on conflict (key) do nothing;

create or replace function public.admin_set_booking_name_visibility(
  p_visible boolean,
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
begin
  if p_visible is null then raise exception 'A beállítás kötelező.' using errcode = '22004'; end if;
  if p_correlation_id is null then raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004'; end if;

  select value into v_before from public.app_settings where key = 'show_other_booker_names' for update;
  update public.app_settings
  set value = to_jsonb(p_visible), updated_by = v_actor_id, updated_at = now()
  where key = 'show_other_booker_names';
  select value into v_after from public.app_settings where key = 'show_other_booker_names';

  if v_before is distinct from v_after then
    insert into public.audit_logs (actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id)
    values (v_actor_id, 'settings.booking_name_visibility.updated', 'app_setting', 'show_other_booker_names',
      jsonb_build_object('value', v_before), jsonb_build_object('value', v_after), p_correlation_id);
  end if;
end;
$$;

create or replace function public.list_calendar_bookings(
  p_start_at timestamptz,
  p_end_at timestamptz
)
returns table (
  booking_id uuid,
  room_id uuid,
  room_name text,
  start_at timestamptz,
  end_at timestamptz,
  use_type public.booking_use_type,
  is_own boolean,
  booker_display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_show_names boolean := true;
begin
  if p_start_at is null or p_end_at is null or p_end_at <= p_start_at then
    raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode = '22023';
  end if;
  if p_end_at - p_start_at > interval '62 days' then
    raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode = '22023';
  end if;

  select * into v_actor from public.profiles where id = auth.uid() and is_active;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode = '42501'; end if;

  select coalesce((value #>> '{}')::boolean, true) into v_show_names
  from public.app_settings where key = 'show_other_booker_names';

  return query
  select booking.id, room.id, room.name, booking.start_at, booking.end_at, booking.use_type,
    booking.user_id = v_actor.id,
    case when v_actor.role = 'admin' or booking.user_id = v_actor.id or v_show_names
      then nullif(btrim(booker.last_name || ' ' || booker.first_name), '') else null end
  from public.bookings booking
  join public.rooms room on room.id = booking.room_id and room.is_active
  join public.profiles booker on booker.id = booking.user_id
  where booking.status = 'active'
    and booking.start_at < p_end_at and booking.end_at > p_start_at
    and (
      v_actor.role = 'admin'
      or exists (select 1 from public.user_room_permissions direct_permission
        where direct_permission.user_id = v_actor.id and direct_permission.room_id = room.id and direct_permission.can_book)
      or exists (select 1 from public.access_group_members membership
        join public.access_groups access_group on access_group.id = membership.group_id and access_group.is_active
        join public.access_group_rooms group_permission on group_permission.group_id = membership.group_id
        where membership.user_id = v_actor.id and group_permission.room_id = room.id and group_permission.can_book)
    )
  order by booking.start_at, room.display_order, booking.id;
end;
$$;

revoke execute on function public.admin_set_booking_name_visibility(boolean,uuid) from public, anon;
grant execute on function public.admin_set_booking_name_visibility(boolean,uuid) to authenticated;

comment on function public.list_calendar_bookings(timestamptz,timestamptz) is
  'Jogosultságszűrt naptár-read model; más foglalók neve globális adminbeállítás alapján látható, admin és saját foglalás mindig névvel.';
comment on column public.profiles.other_booker_names_visible is
  'DEPRECATED: a névláthatóság 2026-08-21-től globális app_setting; kompatibilitási okból a mező egyelőre megmarad.';

commit;
