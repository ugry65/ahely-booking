begin;

alter function public.prevent_physical_delete() set search_path = '';
alter function public.prevent_audit_mutation() set search_path = '';

-- Internal helper: booking RPCs call this under their own SECURITY DEFINER context.
-- It is not part of the public application RPC contract and must not be directly
-- callable by signed-in users through PostgREST.
revoke execute on function public.claim_booking_title_request(uuid,text,text)
  from public, anon, authenticated;

comment on function public.claim_booking_title_request(uuid,text,text) is
  'Internal idempotency helper for booking-title aware write RPCs. Direct API execution is intentionally revoked.';

commit;
