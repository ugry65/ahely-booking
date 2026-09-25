begin;

create or replace function public.assert_booking_request(
  p_actor_id uuid,
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_is_admin boolean;
  v_timezone text;
  v_slot_minutes integer;
  v_minimum_minutes integer;
  v_advance_days integer;
  v_training_advance_days integer;
  v_duration_minutes bigint;
  v_start_local timestamp;
  v_end_local timestamp;
  v_service_date date;
  v_opens_at time;
  v_closes_at time;
begin
  select * into v_actor from public.profiles where id = p_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_room_id is null or p_user_id is null or p_start_at is null or p_end_at is null or p_use_type is null then
    raise exception 'A foglalás kötelező adatai hiányoznak.' using errcode = 'P0001';
  end if;

  if not isfinite(p_start_at) or not isfinite(p_end_at) then
    raise exception 'A foglalás időpontja nem érvényes.' using errcode = 'P0001';
  end if;

  v_is_admin := v_actor.role = 'admin';

  select * into v_target from public.profiles where id = p_user_id;
  if not found or not v_target.is_active then
    raise exception 'A foglalás célfelhasználója nem aktív.' using errcode = 'P0001';
  end if;

  if not v_is_admin and p_user_id <> p_actor_id then
    raise exception 'Más felhasználó nevében csak admin járhat el.' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found or not v_room.is_active then
    raise exception 'A kiválasztott helyiség nem foglalható.' using errcode = 'P0001';
  end if;

  if not v_is_admin and not exists (
    select 1
    from public.effective_room_permissions(p_user_id) permission
    where permission.room_id = p_room_id
      and permission.can_book
  ) then
    raise exception 'Nincs foglalási jogosultságod ehhez a helyiséghez.' using errcode = 'P0001';
  end if;

  select value #>> '{}' into v_timezone from public.app_settings where key = 'timezone';
  select (value #>> '{}')::integer into v_slot_minutes from public.app_settings where key = 'slot_minutes';
  select (value #>> '{}')::integer into v_minimum_minutes from public.app_settings where key = 'minimum_booking_minutes';
  select (value #>> '{}')::integer into v_advance_days from public.app_settings where key = 'default_advance_booking_days';
  select (value #>> '{}')::integer into v_training_advance_days from public.app_settings where key = 'training_room_advance_days';

  if v_timezone is null or v_slot_minutes is null or v_slot_minutes <= 0
    or v_minimum_minutes is null or v_minimum_minutes <= 0
    or v_advance_days is null or v_advance_days < 0
    or v_training_advance_days is null or v_training_advance_days < 0
  then
    raise exception 'A foglalási beállítások hiányosak vagy hibásak.' using errcode = 'P0001';
  end if;

  if p_end_at <= p_start_at then
    raise exception 'A befejezésnek a kezdés után kell lennie.' using errcode = 'P0001';
  end if;

  v_duration_minutes := extract(epoch from (p_end_at - p_start_at))::bigint / 60;
  v_start_local := p_start_at at time zone v_timezone;
  v_end_local := p_end_at at time zone v_timezone;
  v_service_date := v_start_local::date;

  if v_start_local::date <> v_end_local::date then
    raise exception 'A foglalás nem nyúlhat át másik napra.' using errcode = 'P0001';
  end if;

  if v_duration_minutes < v_minimum_minutes then
    raise exception 'A foglalás legalább % perces legyen.', v_minimum_minutes using errcode = 'P0001';
  end if;

  -- A helyi faliidő-rács biztonságos, amíg a nyitvatartás nem érinti a
  -- DST-visszaállás ismétlődő 02:00–03:00 óráját.
  if v_duration_minutes % v_slot_minutes <> 0
    or extract(epoch from v_start_local::time)::bigint % (v_slot_minutes * 60) <> 0
    or extract(epoch from v_end_local::time)::bigint % (v_slot_minutes * 60) <> 0
  then
    raise exception 'A kezdésnek, befejezésnek és időtartamnak % perces rácshoz kell igazodnia.',
      v_slot_minutes using errcode = 'P0001';
  end if;

  if not v_is_admin then
    v_advance_days := coalesce(v_target.advance_booking_days_override, v_advance_days);
    if v_room.is_training_room then
      v_advance_days := least(v_advance_days, v_training_advance_days);
    end if;

    if v_service_date > (clock_timestamp() at time zone v_timezone)::date + v_advance_days then
      if v_room.is_training_room then
        raise exception 'A Tréningterem legfeljebb % napra előre foglalható.', v_advance_days using errcode = 'P0001';
      end if;
      raise exception 'Legfeljebb % napra előre foglalhatsz.', v_advance_days using errcode = 'P0001';
    end if;
  end if;

  if not v_room.is_training_room and p_use_type = 'group' then
    raise exception 'Csoportos használattípus csak a Tréningteremnél választható.' using errcode = 'P0001';
  end if;

  select (value #>> '{}')::time into v_opens_at
  from public.app_settings where key = 'opening_time';
  select (value #>> '{}')::time into v_closes_at
  from public.app_settings where key = 'closing_time';

  if v_opens_at is null or v_closes_at is null or v_closes_at <= v_opens_at then
    raise exception 'A napi foglalási idősáv beállítása hiányzik vagy hibás.' using errcode = 'P0001';
  end if;

  if v_start_local::time < v_opens_at or v_end_local::time > v_closes_at then
    raise exception 'A foglalásnak a %–% közötti nyitvatartásba kell esnie.',
      to_char(v_opens_at, 'HH24:MI'), to_char(v_closes_at, 'HH24:MI') using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.assert_booking_request(
  uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type
) from public, anon, authenticated;

comment on function public.assert_booking_request(
  uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type
) is
  'Közös foglalási validátor. Aktív normál user és admin múltbeli időpontra is foglalhat; a jogosultsági, időrács-, nyitvatartási, előrefoglalási és ütközési szabályok változatlanok.';

commit;
