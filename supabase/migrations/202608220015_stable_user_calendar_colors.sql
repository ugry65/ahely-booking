begin;

alter table public.profiles add column if not exists calendar_color text;

with palette as (
  select color, ordinality
  from unnest(array[
    '#1f77b4','#ff7f0e','#2ca02c','#d62728','#9467bd','#8c564b','#e377c2','#7f7f7f','#bcbd22','#17becf',
    '#393b79','#637939','#8c6d31','#843c39','#7b4173','#3182bd','#31a354','#756bb1','#636363','#e6550d',
    '#6baed6','#74c476','#9e9ac8','#969696','#fd8d3c','#08519c','#006d2c','#54278f','#525252','#a63603',
    '#9c9ede','#cedb9c','#e7ba52','#e7969c','#de9ed6','#6b6ecf','#b5cf6b','#bd9e39','#ad494a','#a55194'
  ]::text[]) with ordinality as p(color, ordinality)
), ranked_profiles as (
  select id, row_number() over (order by created_at, id) as rn
  from public.profiles
  where calendar_color is null
)
update public.profiles profile
set calendar_color = palette.color
from ranked_profiles ranked
join palette on palette.ordinality = ((ranked.rn - 1) % 40) + 1
where profile.id = ranked.id;

alter table public.profiles alter column calendar_color set not null;
alter table public.profiles add constraint profiles_calendar_color_format
  check (calendar_color ~ '^#[0-9A-Fa-f]{6}$');

create or replace function public.assign_profile_calendar_color()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_palette text[] := array[
    '#1f77b4','#ff7f0e','#2ca02c','#d62728','#9467bd','#8c564b','#e377c2','#7f7f7f','#bcbd22','#17becf',
    '#393b79','#637939','#8c6d31','#843c39','#7b4173','#3182bd','#31a354','#756bb1','#636363','#e6550d',
    '#6baed6','#74c476','#9e9ac8','#969696','#fd8d3c','#08519c','#006d2c','#54278f','#525252','#a63603',
    '#9c9ede','#cedb9c','#e7ba52','#e7969c','#de9ed6','#6b6ecf','#b5cf6b','#bd9e39','#ad494a','#a55194'
  ];
begin
  if new.calendar_color is not null then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('profile_calendar_color_assignment', 0));
  select candidate.color into new.calendar_color
  from unnest(v_palette) with ordinality as candidate(color, ordinality)
  left join (
    select calendar_color, count(*) as usage_count
    from public.profiles
    group by calendar_color
  ) usage on usage.calendar_color = candidate.color
  order by coalesce(usage.usage_count, 0), candidate.ordinality
  limit 1;
  return new;
end;
$$;

drop trigger if exists assign_profile_calendar_color_before_insert on public.profiles;
create trigger assign_profile_calendar_color_before_insert
before insert on public.profiles
for each row execute function public.assign_profile_calendar_color();

revoke all on function public.assign_profile_calendar_color() from public, anon, authenticated;

-- Privacy-aware calendar read model: color follows the same visibility rule as the booker identity.
drop function public.list_calendar_bookings(timestamptz,timestamptz);
create function public.list_calendar_bookings(p_start_at timestamptz,p_end_at timestamptz)
returns table(
  booking_id uuid,room_id uuid,room_name text,start_at timestamptz,end_at timestamptz,
  use_type public.booking_use_type,is_own boolean,booker_display_name text,booking_title text,booker_color text
)
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
    case when v_actor.role='admin' or b.user_id=v_actor.id then b.booking_title else null end,
    case when v_actor.role='admin' or b.user_id=v_actor.id or v_show_names then p.calendar_color else null end
  from public.bookings b join public.rooms r on r.id=b.room_id and r.is_active join public.profiles p on p.id=b.user_id
  where b.status='active' and b.start_at<p_end_at and b.end_at>p_start_at
    and (v_actor.role='admin' or exists(select 1 from public.effective_room_permissions(v_actor.id) ep where ep.room_id=r.id and ep.can_book))
  order by b.start_at,r.display_order,b.id;
end; $$;

revoke all on function public.list_calendar_bookings(timestamptz,timestamptz) from public, anon;
grant execute on function public.list_calendar_bookings(timestamptz,timestamptz) to authenticated, service_role;

comment on column public.profiles.calendar_color is 'Tartós naptárszín. Az első 40 userhez 40 külön palettaszín osztható; később a legkevésbé használt szín ismétlődik.';
comment on function public.list_calendar_bookings(timestamptz,timestamptz) is 'Naptári read-model privacy-aware booker névvel, címmel és tartós user-színnel.';

commit;
