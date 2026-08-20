begin;

-- 2026-08-21 business rule:
-- A normal user who can book a normal room may also create recurring bookings there.
-- Training room recurring bookings remain admin-only.
-- Admin is not constrained by room permission or advance-booking limits (enforced by existing RPCs).
create or replace function public.effective_room_permissions(p_user_id uuid)
returns table (
  room_id uuid,
  can_book boolean,
  can_repeat boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with aggregated as (
    select permission.room_id,
           bool_or(permission.can_book) as can_book
    from (
      select direct_permission.room_id,
             direct_permission.can_book
      from public.user_room_permissions direct_permission
      where direct_permission.user_id = p_user_id

      union all

      select group_permission.room_id,
             group_permission.can_book
      from public.access_group_members membership
      join public.access_groups access_group
        on access_group.id = membership.group_id
       and access_group.is_active
      join public.access_group_rooms group_permission
        on group_permission.group_id = membership.group_id
      where membership.user_id = p_user_id
    ) permission
    group by permission.room_id
  )
  select aggregated.room_id,
         aggregated.can_book,
         (aggregated.can_book and not room.is_training_room) as can_repeat
  from aggregated
  join public.rooms room on room.id = aggregated.room_id
$$;

revoke all on function public.effective_room_permissions(uuid)
  from public, anon, authenticated;

comment on function public.effective_room_permissions(uuid) is
  'Effektív helyiségjog: normál helyiségnél can_repeat automatikusan követi a can_book jogot; Tréningterem ismétlődése normál usernek tiltott. Admin bypass a foglalási RPC-kben történik.';

commit;
