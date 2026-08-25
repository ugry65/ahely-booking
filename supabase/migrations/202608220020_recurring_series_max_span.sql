begin;

create or replace function public.enforce_booking_series_safety_cap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last_occurrence date;
begin
  if new.ends_on is not null and new.ends_on > new.starts_on + 366 then
    raise exception 'A sorozat legfeljebb 366 napos lehet az első alkalomtól.' using errcode = 'P0001';
  end if;

  if new.occurrence_count is not null then
    v_last_occurrence := public.recurring_occurrence_date(
      new.starts_on,
      new.frequency,
      new.occurrence_count - 1
    );

    if v_last_occurrence > new.starts_on + 366 then
      raise exception 'A sorozat utolsó alkalma legfeljebb 366 nappal lehet az első alkalom után.' using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists booking_series_safety_cap on public.booking_series;
create trigger booking_series_safety_cap
before insert or update of starts_on, ends_on, occurrence_count, frequency
on public.booking_series
for each row execute function public.enforce_booking_series_safety_cap();

revoke all on function public.enforce_booking_series_safety_cap() from public, anon, authenticated;

comment on function public.enforce_booking_series_safety_cap() is
  'DB-szintű 366 napos sorozatplafon végdátumos és darabszámos ismétlődéshez; a 400 alkalmas külön plafont nem helyettesíti.';

commit;
