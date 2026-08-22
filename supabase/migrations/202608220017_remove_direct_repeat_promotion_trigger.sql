begin;

-- Authenticated clients have no direct table privileges or RLS policy on
-- user_room_permissions. Legacy compatibility is intentionally supported only
-- through the audited admin_set_user_room_permission RPC, which participates in
-- the same profile-first advisory lock order as the canonical user-level repeat
-- permission RPC. Keeping a table trigger would add an unsupported service-role/
-- direct-SQL path with a reversed row-lock -> profile-lock order and could create
-- an avoidable deadlock with an explicit repeat-permission OFF operation.
drop trigger if exists promote_user_repeat_permission_from_legacy
  on public.user_room_permissions;

drop function if exists public.promote_user_repeat_permission_from_legacy();

comment on function public.admin_set_user_room_permission(uuid,uuid,boolean,boolean,uuid) is
  'Auditált kompatibilitási admin RPC közvetlen user–szoba joghoz. A legacy can_repeat=true ugyanebben a tranzakcióban user-szintű repeat jogot kapcsol be; közvetlen kliens-táblaírás nem támogatott.';

commit;
