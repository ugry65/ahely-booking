begin;

create or replace function public.guard_series_training_room_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role public.user_role;
  v_is_training boolean;
begin
  if new.series_id is null then
    return new;
  end if;

  select role into v_actor_role from public.profiles where id = auth.uid() and is_active;
  if v_actor_role = 'admin' then
    return new;
  end if;

  select is_training_room into v_is_training from public.rooms where id = new.room_id;
  if coalesce(v_is_training, false) then
    raise exception 'Ismétlődő Tréningterem-foglalást csak admin kezelhet sorozatként.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger bookings_guard_series_training_update
before update of room_id, start_at, end_at, use_type, note on public.bookings
for each row when (new.series_id is not null)
execute function public.guard_series_training_room_update();

revoke all on function public.guard_series_training_room_update() from public, anon, authenticated;

commit;
