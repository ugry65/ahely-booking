#!/usr/bin/env bash
set -Eeuo pipefail
if [ "${PGHOST:-}" != 127.0.0.1 ] || [ "${PGDATABASE:-}" != training_parity_test ]; then
  echo 'Requires disposable loopback training_parity_test database' >&2; exit 1
fi
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
create table public.bookings(id integer primary key, room_id integer, use_type text,
  group_hourly_rate_huf bigint check(group_hourly_rate_huf>=0));
create function public.apply_training_group_booking_rate() returns trigger language plpgsql as $$
begin
  if new.use_type='group' and new.group_hourly_rate_huf is null then
    new.group_hourly_rate_huf:=5000;
  end if;
  return new;
end $$;
create trigger bookings_training_group_rate_default before insert or update of
room_id,use_type,group_hourly_rate_huf on public.bookings for each row
execute function public.apply_training_group_booking_rate();
insert into public.bookings values(1,1,'group',7500),(2,1,'group',null);
create table before_rows as select * from public.bookings;
create function public.unrelated_guard() returns trigger language plpgsql as $$
begin return new; end $$;
create trigger unrelated_guard before insert on public.bookings for each row execute function public.unrelated_guard();
SQL
psql -X -v ON_ERROR_STOP=1 -f "$root_dir/scripts/lib/retire-legacy-training-rate-default.sql"
psql -X -v ON_ERROR_STOP=1 -f "$root_dir/scripts/lib/retire-legacy-training-rate-default.sql"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if exists((select * from public.bookings except select * from before_rows)
    union all (select * from before_rows except select * from public.bookings)) then
    raise exception 'Existing booking rows changed';
  end if;
  if not exists(select 1 from pg_trigger where tgname='unrelated_guard') then
    raise exception 'Unrelated trigger lost'; end if;
end $$;
insert into public.bookings values(3,1,'group',null);
update public.bookings set room_id=2 where id=3;
do $$ begin
  if (select group_hourly_rate_huf from public.bookings where id=3) is not null then
    raise exception 'Legacy default still applied to new booking'; end if;
  if (select group_hourly_rate_huf from public.bookings where id=1)<>7500 then
    raise exception 'Historical explicit rate lost'; end if;
  if (select group_hourly_rate_huf from public.bookings where id=2)<>5000 then
    raise exception 'Historical default rate lost'; end if;
end $$;
-- Production-shaped schema (legacy column and function absent) also succeeds.
drop table public.bookings;
drop function public.apply_training_group_booking_rate();
create table public.bookings(id integer primary key);
SQL
psql -X -v ON_ERROR_STOP=1 -f "$root_dir/scripts/lib/retire-legacy-training-rate-default.sql"
echo 'Training-rate parity regression PASS'
