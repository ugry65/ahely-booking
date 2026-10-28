#!/usr/bin/env bash
set -Eeuo pipefail
if [ "${PGHOST:-}" != 127.0.0.1 ] || [ "${PGDATABASE:-}" != targeted_migration_test ]; then
  echo 'Requires disposable loopback targeted_migration_test DB.' >&2; exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/supabase/migrations"
printf 'project_id = "targeted-cli-test"\n' > "$work/supabase/config.toml"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
create schema supabase_migrations;
create table supabase_migrations.schema_migrations(version text primary key, statements text[], name text);
create table public.existing_business(id integer primary key, amount integer not null);
insert into public.existing_business values (1, 12345);
insert into supabase_migrations.schema_migrations values (
  '20200101000000', array['create table public.existing_business(id integer primary key, amount integer not null)'], 'existing_business'
);
SQL
db_url="postgresql://postgres:${PGPASSWORD:?}@127.0.0.1:${PGPORT:-5432}/targeted_migration_test?sslmode=disable"
supabase --workdir "$work" migration fetch --db-url "$db_url" --yes
test -f "$work/supabase/migrations/20200101000000_existing_business.sql"
cat > "$work/supabase/migrations/20261028151000_training_group_180_day_limit.sql" <<'SQL'
create function public.synthetic_approved_function() returns integer language sql immutable as 'select 180';
SQL
supabase --workdir "$work" db push --db-url "$db_url" --skip-vault --dry-run
test "$(psql -X -A -t -c 'select count(*) from supabase_migrations.schema_migrations')" = 1
supabase --workdir "$work" db push --db-url "$db_url" --skip-vault --yes
psql -X -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if (select count(*) from supabase_migrations.schema_migrations) <> 2
    or not exists(select 1 from supabase_migrations.schema_migrations where version='20261028151000' and name='training_group_180_day_limit')
    or not exists(select 1 from public.existing_business where id=1 and amount=12345)
    or (select count(*) from public.existing_business) <> 1
    or public.synthetic_approved_function() <> 180
  then raise exception 'Targeted CLI preservation failed'; end if;
end $$;
SQL
# Replaying the fetched historical CREATE TABLE would fail; successful push
# plus intact business fixtures proves only the new version was executed.
echo 'targeted migration real CLI integration PASS'
