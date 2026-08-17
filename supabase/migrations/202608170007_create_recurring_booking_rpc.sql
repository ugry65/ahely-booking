begin;

alter table public.booking_series
  add column room_id uuid not null references public.rooms(id) on delete restrict,
  add column local_start_time time not null,
  add column duration_minutes integer not null check (duration_minutes > 0),
  add column use_type public.booking_use_type not null default 'individual',
  add column note text,
  add column idempotency_key uuid not null,
  add column request_payload jsonb not null,
  add constraint booking_series_idempotency_unique unique (created_by, idempotency_key);

create table public.booking_series_occurrences (
  series_id uuid not null references public.booking_series(id) on delete restrict,
  occurrence_index integer not null check (occurrence_index > 0),
  service_date date not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  status text not null check (status in ('created', 'excluded', 'unavailable')),
  booking_id uuid references public.bookings(id) on delete restrict,
  reason text,
  created_at timestamptz not null default now(),
  primary key (series_id, occurrence_index),
  constraint booking_series_occurrence_result_valid check (
    (status = 'created' and booking_id is not null and reason is null)
    or (status in ('excluded', 'unavailable') and booking_id is null and reason is not null)
  )
);

create unique index booking_series_occurrences_booking_idx
  on public.booking_series_occurrences(booking_id)
  where booking_id is not null;

alter table public.booking_series enable row level security;
alter table public.booking_series_occurrences enable row level security;
revoke all on table public.booking_series from anon, authenticated;
revoke all on table public.booking_series_occurrences from anon, authenticated;

create trigger booking_series_no_physical_delete
before delete on public.booking_series
for each row execute function public.prevent_physical_delete();

create trigger booking_series_occurrences_immutable
before update or delete on public.booking_series_occurrences
for each row execute function public.prevent_audit_mutation();

create or replace function public.recurring_occurrence_date(
  p_starts_on date,
  p_frequency public.recurrence_frequency,
  p_zero_based_index integer
)
returns date
language sql
immutable
set search_path = ''
as $$
  select case p_frequency
    when 'daily' then p_starts_on + p_zero_based_index
    when 'weekly' then p_starts_on + (p_zero_based_index * 7)
    when 'biweekly' then p_starts_on + (p_zero_based_index * 14)
    when 'monthly' then (
      with target_month as (
        select (date_trunc('month', p_starts_on::timestamp)
          + make_interval(months => p_zero_based_index))::date as month_start
      )
      select month_start
        + least(
            extract(day from p_starts_on)::integer,
            extract(day from (month_start + interval '1 month - 1 day'))::integer
          ) - 1
      from target_month
    )
  end
$$;

create or replace function public.booking_series_result(p_series_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'series_id', series.id,
    'created', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'occurrence_index', occurrence.occurrence_index,
          'service_date', occurrence.service_date,
          'start_at', occurrence.start_at,
          'end_at', occurrence.end_at,
          'booking_id', occurrence.booking_id
        ) order by occurrence.occurrence_index
      ) filter (where occurrence.status = 'created'),
      '[]'::jsonb
    ),
    'skipped', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'occurrence_index', occurrence.occurrence_index,
          'service_date', occurrence.service_date,
          'start_at', occurrence.start_at,
          'end_at', occurrence.end_at,
          'status', occurrence.status,
          'reason', occurrence.reason
        ) order by occurrence.occurrence_index
      ) filter (where occurrence.status <> 'created'),
      '[]'::jsonb
    )
  )
  from public.booking_series series
  left join public.booking_series_occurrences occurrence
    on occurrence.series_id = series.id
  where series.id = p_series_id
  group by series.id
$$;

create or replace function public.create_booking_series(
  p_room_id uuid,
  p_user_id uuid,
  p_first_start_at timestamptz,
  p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency,
  p_ends_on date,
  p_occurrence_count integer,
  p_exception_dates date[],
  p_conflict_policy public.conflict_policy,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_room public.rooms%rowtype;
  v_existing public.booking_series%rowtype;
  v_series_id uuid := gen_random_uuid();
  v_timezone text;
  v_starts_on date;
  v_local_start time;
  v_duration_minutes integer;
  v_normalized_note text := nullif(btrim(p_note), '');
  v_exception_dates date[];
  v_request_payload jsonb;
  v_occurrence_index integer := 1;
  v_occurrence_date date;
  v_occurrence_start timestamptz;
  v_occurrence_end timestamptz;
  v_booking_id uuid;
  v_reason text;
begin
  if v_actor_id is null then
    raise exception 'A foglaláshoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;
  if p_idempotency_key is null then
    raise exception 'A kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'booking_series:' || v_actor_id::text || ':' || p_idempotency_key::text, 0
  ));

  select * into v_actor from public.profiles where id = v_actor_id;
  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;
  if p_room_id is null or p_user_id is null
    or p_first_start_at is null or p_first_end_at is null
    or p_frequency is null or p_conflict_policy is null or p_use_type is null
  then
    raise exception 'Az ismétlődő foglalás kötelező adatai hiányoznak.' using errcode = 'P0001';
  end if;
  if (p_ends_on is null) = (p_occurrence_count is null) then
    raise exception 'Végdátum vagy ismétlésszám közül pontosan az egyik kötelező.' using errcode = 'P0001';
  end if;
  if p_occurrence_count is not null and (p_occurrence_count <= 0 or p_occurrence_count > 400) then
    raise exception 'Az ismétlésszám 1 és 400 közötti lehet.' using errcode = 'P0001';
  end if;
  if p_first_end_at <= p_first_start_at then
    raise exception 'A befejezésnek a kezdés után kell lennie.' using errcode = 'P0001';
  end if;

  select value #>> '{}' into v_timezone
  from public.app_settings where key = 'timezone';
  if v_timezone is null then
    raise exception 'Az alkalmazás időzóna-beállítása hiányzik.' using errcode = 'P0001';
  end if;

  v_starts_on := (p_first_start_at at time zone v_timezone)::date;
  v_local_start := (p_first_start_at at time zone v_timezone)::time;
  v_duration_minutes := extract(epoch from (p_first_end_at - p_first_start_at))::integer / 60;

  if p_ends_on is not null and (
    p_ends_on < v_starts_on or p_ends_on > v_starts_on + 366
  ) then
    raise exception 'A sorozat végdátuma legfeljebb 366 nappal lehet az első alkalom után.'
      using errcode = 'P0001';
  end if;

  select coalesce(array_agg(distinct exception_date order by exception_date), '{}'::date[])
  into v_exception_dates
  from unnest(coalesce(p_exception_dates, '{}'::date[])) exception_date;

  v_request_payload := jsonb_build_object(
    'room_id', p_room_id,
    'user_id', p_user_id,
    'first_start_at', p_first_start_at,
    'first_end_at', p_first_end_at,
    'frequency', p_frequency,
    'ends_on', p_ends_on,
    'occurrence_count', p_occurrence_count,
    'exception_dates', to_jsonb(v_exception_dates),
    'conflict_policy', p_conflict_policy,
    'use_type', p_use_type,
    'note', v_normalized_note
  );

  -- Az idempotens visszatérés a később megváltozó jogosultsági, nyitvatartási
  -- és előrefoglalási szabályok előtt történik: egy már sikeres kérés retry-a
  -- mindig az eredeti, eltárolt eredményt adja vissza.
  select * into v_existing
  from public.booking_series
  where created_by = v_actor_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.request_payload = v_request_payload then
      return public.booking_series_result(v_existing.id);
    end if;
    raise exception 'Ezt a kérésazonosítót már más sorozatadatokkal használták.'
      using errcode = 'P0001';
  end if;

  select * into v_target from public.profiles where id = p_user_id;
  if not found or not v_target.is_active then
    raise exception 'A foglalás célfelhasználója nem aktív.' using errcode = 'P0001';
  end if;
  if v_actor.role <> 'admin' and p_user_id <> v_actor_id then
    raise exception 'Más felhasználó nevében csak admin járhat el.' using errcode = 'P0001';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found or not v_room.is_active then
    raise exception 'A kiválasztott helyiség nem foglalható.' using errcode = 'P0001';
  end if;
  if v_actor.role <> 'admin' and not exists (
    select 1
    from public.effective_room_permissions(p_user_id) permission
    where permission.room_id = p_room_id and permission.can_repeat
  ) then
    raise exception 'Nincs ismétlődő foglalási jogosultságod ehhez a helyiséghez.'
      using errcode = 'P0001';
  end if;
  if v_room.is_training_room and v_actor.role <> 'admin' then
    raise exception 'Ismétlődő Tréningterem-foglalást csak admin hozhat létre.'
      using errcode = 'P0001';
  end if;

  insert into public.booking_series (
    id, owner_user_id, created_by, room_id, frequency, timezone,
    starts_on, ends_on, occurrence_count, exception_dates, conflict_policy,
    local_start_time, duration_minutes, use_type, note,
    idempotency_key, request_payload
  ) values (
    v_series_id, p_user_id, v_actor_id, p_room_id, p_frequency, v_timezone,
    v_starts_on, p_ends_on, p_occurrence_count, v_exception_dates, p_conflict_policy,
    v_local_start, v_duration_minutes, p_use_type, v_normalized_note,
    p_idempotency_key, v_request_payload
  );

  loop
    exit when p_occurrence_count is not null and v_occurrence_index > p_occurrence_count;

    v_occurrence_date := public.recurring_occurrence_date(
      v_starts_on, p_frequency, v_occurrence_index - 1
    );
    exit when p_ends_on is not null and v_occurrence_date > p_ends_on;
    if v_occurrence_date > v_starts_on + 366 then
      raise exception 'A sorozat legfeljebb 366 napos lehet.' using errcode = 'P0001';
    end if;

    v_occurrence_start := (v_occurrence_date + v_local_start) at time zone v_timezone;
    v_occurrence_end := v_occurrence_start + make_interval(mins => v_duration_minutes);

    if v_occurrence_date = any(v_exception_dates) then
      insert into public.booking_series_occurrences (
        series_id, occurrence_index, service_date, start_at, end_at, status, reason
      ) values (
        v_series_id, v_occurrence_index, v_occurrence_date,
        v_occurrence_start, v_occurrence_end, 'excluded', 'Kivételdátum.'
      );
      v_occurrence_index := v_occurrence_index + 1;
      continue;
    end if;

    begin
      perform public.assert_booking_request(
        v_actor_id, p_room_id, p_user_id,
        v_occurrence_start, v_occurrence_end, p_use_type
      );

      v_booking_id := gen_random_uuid();
      insert into public.bookings (
        id, room_id, user_id, created_by, series_id,
        start_at, end_at, use_type, note, idempotency_key
      ) values (
        v_booking_id, p_room_id, p_user_id, v_actor_id, v_series_id,
        v_occurrence_start, v_occurrence_end, p_use_type,
        v_normalized_note, gen_random_uuid()
      );

      insert into public.booking_series_occurrences (
        series_id, occurrence_index, service_date, start_at, end_at,
        status, booking_id
      ) values (
        v_series_id, v_occurrence_index, v_occurrence_date,
        v_occurrence_start, v_occurrence_end, 'created', v_booking_id
      );

      insert into public.audit_logs (
        actor_user_id, action, entity_type, entity_id, after_data, correlation_id
      ) values (
        v_actor_id, 'booking.created', 'booking', v_booking_id::text,
        jsonb_build_object(
          'room_id', p_room_id, 'user_id', p_user_id,
          'series_id', v_series_id, 'start_at', v_occurrence_start,
          'end_at', v_occurrence_end, 'use_type', p_use_type
        ),
        p_idempotency_key
      );

      insert into public.outbox_events (
        event_type, aggregate_type, aggregate_id, payload
      ) values (
        'booking.created', 'booking', v_booking_id::text,
        jsonb_build_object(
          'booking_id', v_booking_id,
          'series_id', v_series_id,
          'recipient_user_id', p_user_id
        )
      );
    exception
      when exclusion_violation then
        v_reason := 'A helyiség a kiválasztott időpontban már foglalt.';
        if p_conflict_policy = 'abort_all' then
          raise exception 'A sorozat nem hozható létre. Ütköző alkalom: % (%).',
            v_occurrence_date, v_reason using errcode = 'P0001';
        end if;
        insert into public.booking_series_occurrences (
          series_id, occurrence_index, service_date, start_at, end_at, status, reason
        ) values (
          v_series_id, v_occurrence_index, v_occurrence_date,
          v_occurrence_start, v_occurrence_end, 'unavailable', v_reason
        );
      when raise_exception then
        v_reason := sqlerrm;
        if p_conflict_policy = 'abort_all' then
          raise exception 'A sorozat nem hozható létre. Hibás alkalom: % (%).',
            v_occurrence_date, v_reason using errcode = 'P0001';
        end if;
        insert into public.booking_series_occurrences (
          series_id, occurrence_index, service_date, start_at, end_at, status, reason
        ) values (
          v_series_id, v_occurrence_index, v_occurrence_date,
          v_occurrence_start, v_occurrence_end, 'unavailable', v_reason
        );
      when check_violation then
        -- A constraint neve és a nyers PostgreSQL-hiba nem kerülhet a klienshez.
        v_reason := 'Az alkalom nem felel meg a foglalási szabályoknak.';
        if p_conflict_policy = 'abort_all' then
          raise exception 'A sorozat nem hozható létre. Hibás alkalom: % (%).',
            v_occurrence_date, v_reason using errcode = 'P0001';
        end if;
        insert into public.booking_series_occurrences (
          series_id, occurrence_index, service_date, start_at, end_at, status, reason
        ) values (
          v_series_id, v_occurrence_index, v_occurrence_date,
          v_occurrence_start, v_occurrence_end, 'unavailable', v_reason
        );
    end;

    v_occurrence_index := v_occurrence_index + 1;
  end loop;

  if not exists (
    select 1 from public.booking_series_occurrences
    where series_id = v_series_id and status = 'created'
  ) then
    raise exception 'A sorozatból egyetlen foglalható alkalom sem hozható létre.'
      using errcode = 'P0001';
  end if;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, after_data, correlation_id
  ) values (
    v_actor_id, 'booking_series.created', 'booking_series', v_series_id::text,
    jsonb_build_object(
      'room_id', p_room_id, 'user_id', p_user_id,
      'frequency', p_frequency, 'starts_on', v_starts_on,
      'ends_on', p_ends_on, 'occurrence_count', p_occurrence_count,
      'conflict_policy', p_conflict_policy
    ),
    p_idempotency_key
  );

  return public.booking_series_result(v_series_id);
end;
$$;

revoke all on function public.recurring_occurrence_date(date,public.recurrence_frequency,integer)
  from public, anon, authenticated;
revoke all on function public.booking_series_result(uuid)
  from public, anon, authenticated;
revoke all on function public.create_booking_series(
  uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],
  public.conflict_policy,public.booking_use_type,text,uuid
) from public, anon;
grant execute on function public.create_booking_series(
  uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],
  public.conflict_policy,public.booking_use_type,text,uuid
) to authenticated;

comment on function public.create_booking_series(
  uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],
  public.conflict_policy,public.booking_use_type,text,uuid
) is
  'Tranzakciós és idempotens ismétlődő foglalás napi/heti/kétheti/havi szabállyal, kivételdátumokkal és választható konfliktuspolitikával.';

commit;
