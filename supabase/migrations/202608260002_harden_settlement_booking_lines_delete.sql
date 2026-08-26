begin;

-- A lezárt havi settlement tételsorai történeti pénzügyi snapshotok.
-- A kanonikus baseline szerint sem UPDATE, sem fizikai DELETE nem engedélyezett.
-- A korábbi trigger csak UPDATE-re védett; ezt előrehaladó hardening migrációval
-- kiterjesztjük DELETE-re is, a migrációtörténet visszamenőleges átírása nélkül.
drop trigger if exists settlement_booking_lines_immutable
  on public.settlement_booking_lines;

create trigger settlement_booking_lines_immutable
before update or delete on public.settlement_booking_lines
for each row execute function public.prevent_settlement_snapshot_mutation();

commit;
