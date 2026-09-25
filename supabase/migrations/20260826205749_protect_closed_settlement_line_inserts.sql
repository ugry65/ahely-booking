begin;

-- A lezárási RPC a revision és booking-line sorokat még a monthly_settlements
-- rekord lezárása előtt építi fel. A lezárás után azonban a snapshot teljes
-- tartalma append irányban is immutable: privilegizált közvetlen kapcsolat sem
-- fűzhet hozzá új revisiont vagy booking-line sort.
create or replace function public.prevent_closed_settlement_revision_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.monthly_settlements ms
    where ms.id = new.settlement_id
      and ms.is_closed
  ) then
    raise exception 'Lezárt havi elszámoláshoz nem adható új revision.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger settlement_revisions_reject_insert_after_close
before insert on public.settlement_revisions
for each row execute function public.prevent_closed_settlement_revision_insert();

create or replace function public.prevent_closed_settlement_line_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.monthly_settlements ms
    where ms.closed_revision_id = new.settlement_revision_id
      and ms.is_closed
  ) then
    raise exception 'Lezárt elszámolási snapshothoz nem adható új booking sor.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger settlement_booking_lines_reject_insert_after_close
before insert on public.settlement_booking_lines
for each row execute function public.prevent_closed_settlement_line_insert();

-- A lezárt revisionre mutató kapcsolatot is rögzítjük. A payment backend a
-- settlement status/updated_at mezőit továbbra is módosíthatja, de a lezárás
-- ténye, ideje, végrehajtója és revisionje nem cserélhető vagy nullázható.
create or replace function public.prevent_closed_settlement_metadata_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.is_closed and (
    new.is_closed is distinct from old.is_closed
    or new.closed_at is distinct from old.closed_at
    or new.closed_by is distinct from old.closed_by
    or new.closed_revision_id is distinct from old.closed_revision_id
  ) then
    raise exception 'A lezárt havi elszámolás lezárási adatai nem módosíthatók.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger monthly_settlements_closed_metadata_immutable
before update of is_closed, closed_at, closed_by, closed_revision_id
on public.monthly_settlements
for each row execute function public.prevent_closed_settlement_metadata_mutation();

revoke execute on function public.prevent_closed_settlement_revision_insert()
  from public, anon, authenticated;
revoke execute on function public.prevent_closed_settlement_line_insert()
  from public, anon, authenticated;
revoke execute on function public.prevent_closed_settlement_metadata_mutation()
  from public, anon, authenticated;

commit;
