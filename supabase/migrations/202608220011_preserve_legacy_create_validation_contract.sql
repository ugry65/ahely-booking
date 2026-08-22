begin;

-- Keep the public legacy create_booking contract visibly tied to the shared
-- validator without breaking its original idempotent-retry semantics.
create or replace function public.create_booking(
  p_room_id uuid,
  p_user_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_use_type public.booking_use_type,
  p_note text,
  p_idempotency_key uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_existing_id uuid;
begin
  -- Preserve the legacy implementation's ordering: a null idempotency key and an
  -- already-successful retry are handled by create_booking_base before any
  -- time-dependent validation can change the result.
  if p_idempotency_key is null or v_actor_id is null then
    return public.create_booking_base(
      p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key
    );
  end if;

  select booking.id into v_existing_id
  from public.bookings booking
  where booking.created_by = v_actor_id
    and booking.idempotency_key = p_idempotency_key;

  if found then
    return public.create_booking_base(
      p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key
    );
  end if;

  perform public.assert_booking_request(
    v_actor_id,p_room_id,p_user_id,p_start_at,p_end_at,p_use_type
  );

  return public.create_booking_base(
    p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key
  );
end;
$$;

revoke all on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) from public, anon;
grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) to authenticated, service_role;

commit;
