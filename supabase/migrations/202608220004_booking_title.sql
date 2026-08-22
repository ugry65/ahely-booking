begin;

alter table public.bookings
  add column if not exists booking_title text,
  add constraint bookings_title_length check (booking_title is null or char_length(booking_title) <= 100);

alter table public.booking_series
  add column if not exists booking_title text,
  add constraint booking_series_title_length check (booking_title is null or char_length(booking_title) <= 100);

create table if not exists public.booking_title_requests (
  actor_user_id uuid not null references public.profiles(id) on delete restrict,
  idempotency_key uuid not null,
  operation text not null,
  booking_title text,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, idempotency_key, operation),
  constraint booking_title_requests_operation check (operation in ('create','update','scope_update','series_create')),
  constraint booking_title_requests_length check (booking_title is null or char_length(booking_title) <= 100)
);

create or replace function public.claim_booking_title_request(p_idempotency_key uuid, p_operation text, p_booking_title text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_title text := nullif(btrim(p_booking_title), '');
  v_existing public.booking_title_requests%rowtype;
begin
  if v_actor_id is null then raise exception 'Bejelentkezés szükséges.' using errcode='P0001'; end if;
  if p_idempotency_key is null then raise exception 'A kérésazonosító megadása kötelező.' using errcode='P0001'; end if;
  if p_operation not in ('create','update','scope_update','series_create') then raise exception 'Érvénytelen művelet.' using errcode='P0001'; end if;
  if v_title is not null and char_length(v_title) > 100 then raise exception 'A foglalás címe legfeljebb 100 karakteres lehet.' using errcode='P0001'; end if;
  insert into public.booking_title_requests(actor_user_id,idempotency_key,operation,booking_title)
  values(v_actor_id,p_idempotency_key,p_operation,v_title)
  on conflict do nothing;
  select * into v_existing from public.booking_title_requests
  where actor_user_id=v_actor_id and idempotency_key=p_idempotency_key and operation=p_operation;
  if v_existing.booking_title is distinct from v_title then
    raise exception 'Ezt a kérésazonosítót már más foglalási címmel használták.' using errcode='P0001';
  end if;
  return v_title;
end;
$$;

alter function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) rename to create_booking_base;
create function public.create_booking(
  p_room_id uuid, p_user_id uuid, p_start_at timestamptz, p_end_at timestamptz,
  p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid, p_booking_title text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'create',p_booking_title);
  v_id := public.create_booking_base(p_room_id,p_user_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=v_id and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking.title_set','booking',v_id::text,jsonb_build_object('booking_title_changed',true),p_idempotency_key);
  end if;
  return v_id;
end; $$;

alter function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) rename to update_booking_base;
create function public.update_booking(
  p_booking_id uuid, p_expected_updated_at timestamptz, p_room_id uuid, p_start_at timestamptz,
  p_end_at timestamptz, p_use_type public.booking_use_type, p_note text, p_idempotency_key uuid,
  p_booking_title text default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'update',p_booking_title);
  v_id := public.update_booking_base(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=v_id and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking.title_changed','booking',v_id::text,jsonb_build_object('booking_title_changed',true),p_idempotency_key);
  end if;
  return v_id;
end; $$;

alter function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid) rename to update_booking_scope_base;
create function public.update_booking_scope(
  p_booking_id uuid, p_scope text, p_expected_updated_at timestamptz, p_room_id uuid,
  p_start_at timestamptz, p_end_at timestamptz, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid, p_booking_title text default null
) returns integer language plpgsql security definer set search_path='' as $$
declare v_selected public.bookings%rowtype; v_ids uuid[]; v_count integer; v_title text;
begin
  select * into v_selected from public.bookings where id=p_booking_id;
  if not found then raise exception 'A foglalás nem található.' using errcode='P0001'; end if;
  if v_selected.series_id is null then
    perform public.update_booking(p_booking_id,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key,p_booking_title);
    return 1;
  end if;
  v_title := public.claim_booking_title_request(p_idempotency_key,'scope_update',p_booking_title);
  select array_agg(b.id order by b.start_at,b.id) into v_ids
  from public.bookings b
  where b.series_id=v_selected.series_id and b.status='active' and b.start_at>clock_timestamp()
    and (p_scope='series' or (p_scope='following' and b.start_at>=v_selected.start_at) or (p_scope='occurrence' and b.id=p_booking_id));
  v_count := public.update_booking_scope_base(p_booking_id,p_scope,p_expected_updated_at,p_room_id,p_start_at,p_end_at,p_use_type,p_note,p_idempotency_key);
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp()
  where id=any(coalesce(v_ids,'{}'::uuid[])) and booking_title is distinct from v_title;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
    values(auth.uid(),'booking_series.title_changed','booking_series',v_selected.series_id::text,jsonb_build_object('scope',p_scope,'booking_title_changed',true),p_idempotency_key);
  end if;
  return v_count;
end; $$;

alter function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid) rename to create_booking_series_base;
create function public.create_booking_series(
  p_room_id uuid, p_user_id uuid, p_first_start_at timestamptz, p_first_end_at timestamptz,
  p_frequency public.recurrence_frequency, p_ends_on date, p_occurrence_count integer,
  p_exception_dates date[], p_conflict_policy public.conflict_policy, p_use_type public.booking_use_type,
  p_note text, p_idempotency_key uuid, p_booking_title text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb; v_series_id uuid; v_title text;
begin
  v_title := public.claim_booking_title_request(p_idempotency_key,'series_create',p_booking_title);
  v_result := public.create_booking_series_base(p_room_id,p_user_id,p_first_start_at,p_first_end_at,p_frequency,p_ends_on,p_occurrence_count,p_exception_dates,p_conflict_policy,p_use_type,p_note,p_idempotency_key);
  v_series_id := (v_result->>'series_id')::uuid;
  update public.booking_series set booking_title=v_title where id=v_series_id and booking_title is distinct from v_title;
  update public.bookings set booking_title=v_title, updated_at=clock_timestamp() where series_id=v_series_id and booking_title is distinct from v_title;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,after_data,correlation_id)
  values(auth.uid(),'booking_series.title_set','booking_series',v_series_id::text,jsonb_build_object('booking_title_changed',v_title is not null),p_idempotency_key);
  return v_result;
end; $$;

-- Public calendar: title is deliberately private. It is returned only to the owner or admin.
drop function public.list_calendar_bookings(timestamptz,timestamptz);
create function public.list_calendar_bookings(p_start_at timestamptz,p_end_at timestamptz)
returns table(booking_id uuid,room_id uuid,room_name text,start_at timestamptz,end_at timestamptz,use_type public.booking_use_type,is_own boolean,booker_display_name text,booking_title text)
language plpgsql stable security definer set search_path='' as $$
declare v_actor public.profiles%rowtype; v_show_names boolean:=true;
begin
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode='22023'; end if;
  if p_end_at-p_start_at>interval '62 days' then raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode='22023'; end if;
  select * into v_actor from public.profiles where id=auth.uid() and is_active;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  select coalesce((value#>>'{}')::boolean,true) into v_show_names from public.app_settings where key='show_other_booker_names';
  return query
  select b.id,r.id,r.name,b.start_at,b.end_at,b.use_type,b.user_id=v_actor.id,
    case when v_actor.role='admin' or b.user_id=v_actor.id or v_show_names then nullif(btrim(p.last_name||' '||p.first_name),'') else null end,
    case when v_actor.role='admin' or b.user_id=v_actor.id then b.booking_title else null end
  from public.bookings b join public.rooms r on r.id=b.room_id and r.is_active join public.profiles p on p.id=b.user_id
  where b.status='active' and b.start_at<p_end_at and b.end_at>p_start_at
    and (v_actor.role='admin' or exists(select 1 from public.effective_room_permissions(v_actor.id) ep where ep.room_id=r.id and ep.can_book))
  order by b.start_at,r.display_order,b.id;
end; $$;

drop function public.list_calendar_booking_management(timestamptz,timestamptz);
create function public.list_calendar_booking_management(p_start_at timestamptz,p_end_at timestamptz)
returns table(booking_id uuid,note text,booking_title text,series_id uuid,updated_at timestamptz,can_manage boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_actor public.profiles%rowtype;
begin
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then raise exception 'Érvényes lekérdezési időszak szükséges.' using errcode='22023'; end if;
  if p_end_at-p_start_at>interval '62 days' then raise exception 'Legfeljebb 62 napos időszak kérdezhető le.' using errcode='22023'; end if;
  select * into v_actor from public.profiles where id=auth.uid() and is_active;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  return query select b.id,b.note,b.booking_title,b.series_id,b.updated_at,true
  from public.bookings b join public.rooms r on r.id=b.room_id and r.is_active
  where b.status='active' and b.start_at<p_end_at and b.end_at>p_start_at and (v_actor.role='admin' or b.user_id=v_actor.id)
  order by b.start_at,b.id;
end; $$;

drop function public.list_my_bookings();
create function public.list_my_bookings()
returns table(booking_id uuid,room_id uuid,room_name text,start_at timestamptz,end_at timestamptz,use_type public.booking_use_type,note text,booking_title text,series_id uuid,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_actor public.profiles%rowtype;
begin
  select * into v_actor from public.profiles where id=auth.uid() and is_active;
  if not found then raise exception 'A felhasználói fiók nem aktív.' using errcode='42501'; end if;
  return query select b.id,r.id,r.name,b.start_at,b.end_at,b.use_type,b.note,b.booking_title,b.series_id,b.updated_at
  from public.bookings b join public.rooms r on r.id=b.room_id
  where b.user_id=v_actor.id and b.status='active' and b.start_at>now()
  order by b.start_at,r.display_order,b.id;
end; $$;

grant execute on function public.create_booking(uuid,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking(uuid,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.update_booking_scope(uuid,text,timestamptz,uuid,timestamptz,timestamptz,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.create_booking_series(uuid,uuid,timestamptz,timestamptz,public.recurrence_frequency,date,integer,date[],public.conflict_policy,public.booking_use_type,text,uuid,text) to authenticated, service_role;
grant execute on function public.list_calendar_bookings(timestamptz,timestamptz) to authenticated, service_role;
grant execute on function public.list_calendar_booking_management(timestamptz,timestamptz) to authenticated, service_role;
grant execute on function public.list_my_bookings() to authenticated, service_role;

commit;
