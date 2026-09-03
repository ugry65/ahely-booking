begin;

-- Booking RPCs already write a complete, correlated audit trail. A deferred
-- constraint trigger turns that trail into exactly one immutable e-mail snapshot
-- after every logical operation has finished (including title/rate side effects),
-- while still remaining inside the booking transaction.
create or replace function public.enqueue_booking_email_from_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series_audit public.audit_logs%rowtype;
  v_booking_audit public.audit_logs%rowtype;
  v_actor public.profiles%rowtype;
  v_recipient public.profiles%rowtype;
  v_booking public.bookings%rowtype;
  v_event_type text;
  v_scope text;
  v_booking_id uuid;
  v_series_id uuid;
  v_recipient_user_id uuid;
  v_affected_count integer;
  v_room_id uuid;
  v_room_name text;
  v_before_room_name text;
  v_booking_title text;
  v_use_type text;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_first_start_at timestamptz;
  v_last_end_at timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_payload jsonb;
begin
  select audit.* into v_series_audit
  from public.audit_logs audit
  where audit.correlation_id = new.correlation_id
    and audit.action in (
      'booking_series.created',
      'booking_series.updated',
      'booking_series.cancelled'
    )
  order by audit.id desc
  limit 1;

  if found then
    v_series_id := v_series_audit.entity_id::uuid;
    v_event_type := case v_series_audit.action
      when 'booking_series.created' then 'booking.created'
      when 'booking_series.updated' then 'booking.updated'
      when 'booking_series.cancelled' then 'booking.cancelled'
    end;
    v_scope := case
      when v_series_audit.action = 'booking_series.created' then 'series'
      else coalesce(v_series_audit.after_data ->> 'scope', 'series')
    end;
    v_booking_id := case
      when v_scope = 'occurrence'
      then nullif(v_series_audit.after_data ->> 'selected_booking_id', '')::uuid
      else null
    end;

    select series.owner_user_id into v_recipient_user_id
    from public.booking_series series
    where series.id = v_series_id;

    select
      count(*)::integer,
      min(
        case v_event_type
          when 'booking.cancelled' then (audit.before_data ->> 'start_at')::timestamptz
          else (audit.after_data ->> 'start_at')::timestamptz
        end
      ),
      max(
        case v_event_type
          when 'booking.cancelled' then (audit.before_data ->> 'end_at')::timestamptz
          else (audit.after_data ->> 'end_at')::timestamptz
        end
      )
    into v_affected_count, v_first_start_at, v_last_end_at
    from public.audit_logs audit
    where audit.correlation_id = new.correlation_id
      and audit.action = v_event_type
      and audit.entity_type = 'booking';

    if v_affected_count = 0
      or v_affected_count is distinct from
        coalesce(
          nullif(v_series_audit.after_data ->> 'affected_count', '')::integer,
          v_affected_count
        )
    then
      raise exception 'A sorozatművelet e-mail auditösszesítése nem konzisztens.'
        using errcode = 'P0001';
    end if;

    select audit.* into v_booking_audit
    from public.audit_logs audit
    where audit.correlation_id = new.correlation_id
      and audit.action = v_event_type
      and audit.entity_type = 'booking'
    order by
      case v_event_type
        when 'booking.cancelled' then (audit.before_data ->> 'start_at')::timestamptz
        else (audit.after_data ->> 'start_at')::timestamptz
      end,
      audit.id
    limit 1;
  else
    select audit.* into v_booking_audit
    from public.audit_logs audit
    where audit.correlation_id = new.correlation_id
      and audit.action in ('booking.created', 'booking.updated', 'booking.cancelled')
      and audit.entity_type = 'booking'
    order by audit.id
    limit 1;

    if not found then
      return new;
    end if;

    v_event_type := v_booking_audit.action;
    v_booking_id := v_booking_audit.entity_id::uuid;
    select booking.* into v_booking
    from public.bookings booking
    where booking.id = v_booking_id;

    if not found then
      raise exception 'Az e-mailhez tartozó foglalás nem található.' using errcode = 'P0001';
    end if;

    v_series_id := v_booking.series_id;
    v_scope := case when v_series_id is null then 'single' else 'occurrence' end;
    v_recipient_user_id := v_booking.user_id;
    v_affected_count := 1;
    v_first_start_at := case v_event_type
      when 'booking.cancelled' then (v_booking_audit.before_data ->> 'start_at')::timestamptz
      else coalesce(
        (v_booking_audit.after_data ->> 'start_at')::timestamptz,
        v_booking.start_at
      )
    end;
    v_last_end_at := case v_event_type
      when 'booking.cancelled' then (v_booking_audit.before_data ->> 'end_at')::timestamptz
      else coalesce(
        (v_booking_audit.after_data ->> 'end_at')::timestamptz,
        v_booking.end_at
      )
    end;
  end if;

  if exists (
    select 1
    from public.booking_email_outbox email
    where email.correlation_id = new.correlation_id
      and email.event_type = v_event_type
      and email.recipient_user_id = v_recipient_user_id
  ) then
    return new;
  end if;

  select profile.* into v_actor
  from public.profiles profile
  where profile.id = v_booking_audit.actor_user_id;

  select profile.* into v_recipient
  from public.profiles profile
  where profile.id = v_recipient_user_id;

  if v_actor.id is null or v_recipient.id is null
    or nullif(btrim(v_recipient.email), '') is null
  then
    raise exception 'Az e-mail címzettje vagy műveletvégzője nem oldható fel.' using errcode = 'P0001';
  end if;

  if v_booking_id is not null then
    select booking.* into v_booking
    from public.bookings booking
    where booking.id = v_booking_id;
  else
    select booking.* into v_booking
    from public.bookings booking
    where booking.series_id = v_series_id
      and exists (
        select 1
        from public.audit_logs audit
        where audit.correlation_id = new.correlation_id
          and audit.action = v_event_type
          and audit.entity_type = 'booking'
          and audit.entity_id = booking.id::text
      )
    order by booking.start_at, booking.id
    limit 1;
  end if;

  if v_booking.id is null then
    raise exception 'Az e-mail adatpillanatához nem található foglalás.' using errcode = 'P0001';
  end if;

  v_before := v_booking_audit.before_data;
  v_after := v_booking_audit.after_data;
  v_room_id := case v_event_type
    when 'booking.cancelled' then (v_before ->> 'room_id')::uuid
    else coalesce((v_after ->> 'room_id')::uuid, v_booking.room_id)
  end;

  select room.name into v_room_name
  from public.rooms room
  where room.id = v_room_id;

  if v_event_type = 'booking.updated' then
    select room.name into v_before_room_name
    from public.rooms room
    where room.id = (v_before ->> 'room_id')::uuid;
  end if;

  v_booking_title := case v_event_type
    when 'booking.cancelled' then nullif(v_before ->> 'booking_title', '')
    else v_booking.booking_title
  end;
  v_use_type := case v_event_type
    when 'booking.cancelled' then v_before ->> 'use_type'
    else coalesce(v_after ->> 'use_type', v_booking.use_type::text)
  end;
  v_start_at := case v_event_type
    when 'booking.cancelled' then (v_before ->> 'start_at')::timestamptz
    else coalesce((v_after ->> 'start_at')::timestamptz, v_booking.start_at)
  end;
  v_end_at := case v_event_type
    when 'booking.cancelled' then (v_before ->> 'end_at')::timestamptz
    else coalesce((v_after ->> 'end_at')::timestamptz, v_booking.end_at)
  end;

  if v_room_name is null or v_start_at is null or v_end_at is null or v_use_type is null then
    raise exception 'Az e-mail adatpillanata hiányos.' using errcode = 'P0001';
  end if;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'recipient_name', nullif(btrim(v_recipient.last_name || ' ' || v_recipient.first_name), ''),
    'room_name', v_room_name,
    'start_at', v_start_at,
    'end_at', v_end_at,
    'use_type', v_use_type,
    'booking_title', v_booking_title,
    'scope', v_scope,
    'affected_count', v_affected_count,
    'first_start_at', v_first_start_at,
    'last_end_at', v_last_end_at,
    'performed_by_admin', v_actor.role = 'admin',
    'cancellation_reason', case
      when v_event_type = 'booking.cancelled' then v_booking_audit.reason
      else null
    end,
    'before', case when v_event_type = 'booking.updated' then jsonb_strip_nulls(jsonb_build_object(
      'room_name', v_before_room_name,
      'start_at', (v_before ->> 'start_at')::timestamptz,
      'end_at', (v_before ->> 'end_at')::timestamptz,
      'use_type', v_before ->> 'use_type',
      'booking_title', nullif(v_before ->> 'booking_title', '')
    )) else null end,
    'after', case when v_event_type = 'booking.updated' then jsonb_strip_nulls(jsonb_build_object(
      'room_name', v_room_name,
      'start_at', v_start_at,
      'end_at', v_end_at,
      'use_type', v_use_type,
      'booking_title', v_booking_title
    )) else null end
  ));

  perform public.enqueue_booking_email(
    new.correlation_id,
    v_event_type,
    v_scope,
    v_booking_id,
    v_series_id,
    v_recipient_user_id,
    v_recipient.email,
    v_booking_audit.actor_user_id,
    v_actor.role = 'admin',
    1,
    v_payload
  );

  return new;
end;
$$;

revoke all on function public.enqueue_booking_email_from_audit()
  from public, anon, authenticated, service_role;

create constraint trigger booking_email_from_audit
after insert on public.audit_logs
deferrable initially deferred
for each row
when (
  new.action in (
    'booking.created',
    'booking.updated',
    'booking.cancelled',
    'booking_series.created',
    'booking_series.updated',
    'booking_series.cancelled'
  )
)
execute function public.enqueue_booking_email_from_audit();

comment on function public.enqueue_booking_email_from_audit() is
  'Deferred internal bridge from canonical booking audit correlations to one immutable owner e-mail snapshot per logical operation.';

commit;
