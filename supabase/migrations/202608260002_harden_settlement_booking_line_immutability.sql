begin;

-- A settlement booking-line snapshot történeti pénzügyi bizonyíték. A korábbi
-- trigger csak UPDATE ellen védett; DELETE ellen is ugyanazt az immutable
-- adatbázis-invariánst kell kikényszeríteni.
drop trigger if exists settlement_booking_lines_immutable
on public.settlement_booking_lines;

create trigger settlement_booking_lines_immutable
before update or delete on public.settlement_booking_lines
for each row execute function public.prevent_settlement_snapshot_mutation();

commit;
