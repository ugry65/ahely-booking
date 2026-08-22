begin;

-- Canonical A-Hely room groups. Existing direct user-room permissions are intentionally
-- untouched: they remain an independent source of effective booking/repeat rights.
insert into public.access_groups (id, name, is_active)
select gen_random_uuid(), source.name, true
from (values
  ('A-Hely'::text),
  ('Másik Hely'::text),
  ('Tréningterem'::text),
  ('Forrás tér'::text)
) as source(name)
where not exists (
  select 1 from public.access_groups existing where existing.name = source.name
);

update public.access_groups
set is_active = true
where name in ('A-Hely','Másik Hely','Tréningterem','Forrás tér')
  and not is_active;

-- The four canonical groups have an exact room composition. Group access grants only
-- can_book; recurring permission remains a direct user-level business rule.
delete from public.access_group_rooms mapping
using public.access_groups group_row, public.rooms room
where mapping.group_id = group_row.id
  and mapping.room_id = room.id
  and group_row.name in ('A-Hely','Másik Hely','Tréningterem','Forrás tér')
  and not (
    (group_row.name = 'A-Hely' and room.name in ('Gyerek szoba','Pitypang szoba','Csoport szoba'))
    or (group_row.name = 'Másik Hely' and room.name in ('1.Szoba-családi','2.Szoba','3.Szoba','4.Szoba','5.Szoba','6.Szoba'))
    or (group_row.name = 'Tréningterem' and room.name = 'Tréningterem')
    or (group_row.name = 'Forrás tér' and room.name = 'Forrás tér')
  );

insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat)
select group_row.id, room.id, true, false
from public.access_groups group_row
join public.rooms room on (
  (group_row.name = 'A-Hely' and room.name in ('Gyerek szoba','Pitypang szoba','Csoport szoba'))
  or (group_row.name = 'Másik Hely' and room.name in ('1.Szoba-családi','2.Szoba','3.Szoba','4.Szoba','5.Szoba','6.Szoba'))
  or (group_row.name = 'Tréningterem' and room.name = 'Tréningterem')
  or (group_row.name = 'Forrás tér' and room.name = 'Forrás tér')
)
where group_row.name in ('A-Hely','Másik Hely','Tréningterem','Forrás tér')
on conflict (group_id, room_id) do update set
  can_book = true,
  can_repeat = false;

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
  select permission.room_id,
         bool_or(permission.can_book) as can_book,
         bool_or(permission.can_repeat) as can_repeat
  from (
    select direct_permission.room_id,
           direct_permission.can_book,
           direct_permission.can_repeat
    from public.user_room_permissions direct_permission
    where direct_permission.user_id = p_user_id

    union all

    select group_permission.room_id,
           group_permission.can_book,
           false as can_repeat
    from public.access_group_members membership
    join public.access_groups access_group
      on access_group.id = membership.group_id
     and access_group.is_active
    join public.access_group_rooms group_permission
      on group_permission.group_id = membership.group_id
    where membership.user_id = p_user_id
  ) permission
  group by permission.room_id
$$;

create or replace function public.admin_set_group_room_permission(
  p_group_id uuid,
  p_room_id uuid,
  p_can_book boolean,
  p_can_repeat boolean,
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
  if p_correlation_id is null then
    raise exception 'A korrelációs azonosító kötelező.' using errcode = '22004';
  end if;
  if coalesce(p_can_repeat, false) then
    raise exception 'Helyiségcsoport nem adhat ismétlődő foglalási jogosultságot.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.access_groups where id = p_group_id) then
    raise exception 'A csoport nem található.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.rooms where id = p_room_id) then
    raise exception 'A helyiség nem található.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'access_group_room_permission:' || p_group_id::text || ':' || p_room_id::text, 0
  ));
  select to_jsonb(permission) into v_before
  from public.access_group_rooms permission
  where group_id = p_group_id and room_id = p_room_id
  for update;

  insert into public.access_group_rooms (group_id, room_id, can_book, can_repeat)
  values (p_group_id, p_room_id, coalesce(p_can_book, false), false)
  on conflict (group_id, room_id) do update set
    can_book = excluded.can_book,
    can_repeat = false;

  select to_jsonb(permission) into v_after
  from public.access_group_rooms permission
  where group_id = p_group_id and room_id = p_room_id;

  if v_before is distinct from v_after then
    insert into public.audit_logs (
      actor_user_id, action, entity_type, entity_id, before_data, after_data, correlation_id
    ) values (
      v_actor_id, 'access_group_room_permission.set', 'access_group_room_permission',
      p_group_id::text || ':' || p_room_id::text, v_before, v_after, p_correlation_id
    );
  end if;
end;
$$;

revoke all on function public.effective_room_permissions(uuid) from public, anon, authenticated;
revoke execute on function public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid) from public, anon;
grant execute on function public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid) to authenticated;

comment on function public.effective_room_permissions(uuid) is
  'Effektív helyiségjog: can_book közvetlen vagy aktív helyiségcsoportból, can_repeat kizárólag közvetlen user-room jogosultságból.';
comment on function public.admin_set_group_room_permission(uuid,uuid,boolean,boolean,uuid) is
  'Admin helyiségcsoport-szoba jogosultságkezelés. A csoport csak can_book jogot adhat; repeat jog user-szinten kezelendő.';

commit;
