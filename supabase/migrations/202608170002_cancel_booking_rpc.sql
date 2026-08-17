begin;

create table public.booking_operation_requests (
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key uuid not null,
  operation text not null check (operation in ('update', 'cancel')),
  booking_id uuid not null references public.bookings(id) on delete restrict,
  request_payload jsonb not null,
  result_payload jsonb,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, idempotency_key)
);

alter table public.booking_operation_requests enable row level security;

create trigger booking_operation_requests_no_physical_delete
before delete on public.booking_operation_requests
for each row execute function public.prevent_physical_delete();

alter table public.booking_cancellations
  add column idempotency_key uuid,
  add column settlement_excluded boolean not null default true,
  add constraint booking_cancellations_settlement_excluded check (settlement_excluded);

update public.booking_cancellations
set idempotency_key = gen_random_uuid()
where idempotency_key is null;

alter table public.booking_cancellations
  alter column idempotency_key set not null,
  add constraint booking_cancellations_actor_idempotency_unique
    unique (cancelled_by, idempotency_key);

create trigger booking_cancellations_immutable
before update or delete on public.booking_cancellations
for each row execute function public.prevent_audit_mutation();

create or replace function public.cancel_booking(
  p_booking_id uuid,
  p_reason text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor public.profiles%rowtype;
  v_booking public.bookings%rowtype;
  v_request_payload jsonb;
  v_existing_request public.booking_operation_requests%rowtype;
  v_cutoff_hours integer;
  v_minutes_before_start integer;
  v_reason text := nullif(trim(p_reason), '');
begin
  if v_actor_id is null then
    raise exception 'A lemondáshoz bejelentkezés szükséges.' using errcode = 'P0001';
  end if;

  select * into v_actor
  from public.profiles
  where id = v_actor_id;

  if not found or not v_actor.is_active then
    raise exception 'A felhasználói fiók nem aktív.' using errcode = 'P0001';
  end if;

  if p_booking_id is null or p_idempotency_key is null then
    raise exception 'A foglalás és a kérésazonosító megadása kötelező.' using errcode = 'P0001';
  end if;

  v_request_payload := jsonb_build_object(
    'operation', 'cancel',
    'booking_id', p_booking_id,
    'reason', v_reason
  );

  perform 1 from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'A foglalás nem található.' using errcode = 'P0001';
  end if;

  begin
    insert into public.booking_operation_requests (
      actor_user_id, idempotency_key, operation, booking_id, request_payload
    ) values (
      v_actor_id, p_idempotency_key, 'cancel', p_booking_id, v_request_payload
    );
  exception
    when unique_violation then
      select * into v_existing_request
      from public.booking_operation_requests
      where actor_user_id = v_actor_id
        and idempotency_key = p_idempotency_key;

      if found
        and v_existing_request.operation = 'cancel'
        and v_existing_request.booking_id = p_booking_id
        and v_existing_request.request_payload = v_request_payload
        and v_existing_request.result_payload is not null
      then
        return (v_existing_request.result_payload ->> 'booking_id')::uuid;
      end if;

      raise exception 'Ezt a kérésazonosítót már más műveleti adatokkal használták.' using errcode = 'P0001';
  end;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if v_booking.status <> 'active' then
    raise exception 'A foglalás már le van mondva.' using errcode = 'P0001';
  end if;

  if v_actor.role <> 'admin' and v_booking.user_id <> v_actor_id then
    raise exception 'Csak a saját foglalásodat mondhatod le.' using errcode = 'P0001';
  end if;

  select (value #>> '{}')::integer into v_cutoff_hours
  from public.app_settings
  where key = 'cancellation_cutoff_hours';

  if v_cutoff_hours is null or v_cutoff_hours < 0 then
    raise exception 'A lemondási határidő beállítása hiányzik vagy hibás.' using errcode = 'P0001';
  end if;

  if v_actor.role <> 'admin'
    and clock_timestamp() > v_booking.start_at - make_interval(hours => v_cutoff_hours)
  then
    raise exception 'A foglalás % órán belül már nem mondható le.', v_cutoff_hours using errcode = 'P0001';
  end if;

  v_minutes_before_start := floor(extract(epoch from (v_booking.start_at - clock_timestamp())) / 60)::integer;

  update public.bookings
  set status = 'cancelled', updated_at = clock_timestamp()
  where id = p_booking_id;

  insert into public.booking_cancellations (
    booking_id,
    cancelled_by,
    minutes_before_start,
    reason,
    original_snapshot,
    idempotency_key,
    settlement_excluded
  ) values (
    p_booking_id,
    v_actor_id,
    v_minutes_before_start,
    v_reason,
    to_jsonb(v_booking),
    p_idempotency_key,
    true
  );

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason,
    correlation_id
  ) values (
    v_actor_id,
    'booking.cancelled',
    'booking',
    p_booking_id::text,
    to_jsonb(v_booking),
    jsonb_build_object('status', 'cancelled', 'settlement_excluded', true),
    v_reason,
    p_idempotency_key
  );

  insert into public.outbox_events (
    event_type, aggregate_type, aggregate_id, payload
  ) values (
    'booking.cancelled',
    'booking',
    p_booking_id::text,
    jsonb_build_object(
      'booking_id', p_booking_id,
      'recipient_user_id', v_booking.user_id,
      'settlement_excluded', true
    )
  );

  update public.booking_operation_requests
  set result_payload = jsonb_build_object(
    'booking_id', p_booking_id,
    'status', 'cancelled',
    'settlement_excluded', true
  )
  where actor_user_id = v_actor_id
    and idempotency_key = p_idempotency_key;

  return p_booking_id;
end;
$$;

revoke all on table public.booking_operation_requests from public, anon, authenticated;
revoke all on function public.cancel_booking(uuid, text, uuid) from public, anon;
grant execute on function public.cancel_booking(uuid, text, uuid) to authenticated;

comment on table public.booking_operation_requests is
  'Foglalásmódosítási és lemondási műveletek tranzakciós idempotencia-ledgere.';
comment on column public.booking_cancellations.settlement_excluded is
  'Jóváhagyott üzleti döntés: minden szabályosan lemondott foglalás 0 Ft és kimarad az elszámolásból.';
comment on function public.cancel_booking(uuid, text, uuid) is
  'Történetmegőrző, auditált, idempotens lemondás 24 órás user-határidővel és admin felülbírálással.';

commit;
