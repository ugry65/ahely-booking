#!/usr/bin/env bash
set -Eeuo pipefail

# Supabase CLI 2.116/2.117 still runs pg_dump 15.8, which cannot dump the
# staging project's PostgreSQL 17 server. Keep the CLI's filtering semantics,
# but execute the dump with a pinned PostgreSQL 17 client image.
readonly PG_DUMP_IMAGE="postgres:17.6-bookworm"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <staging-db-url> <output-directory>" >&2
  exit 1
fi

db_url="$1"
output_dir="$2"

if ! command -v docker >/dev/null 2>&1; then
  echo "Missing required command: docker" >&2
  exit 1
fi

mkdir -p "$output_dir"

run_postgres() {
  DATABASE_URL="$db_url" docker run --rm \
    -e DATABASE_URL \
    "$PG_DUMP_IMAGE" "$@"
}

client_version="$(run_postgres pg_dump --version)"
if [[ "$client_version" != "pg_dump (PostgreSQL) 17.6" ]]; then
  echo "Unexpected pg_dump client: $client_version" >&2
  exit 1
fi

server_major="$(run_postgres bash -ceu 'psql -X -A -t -v ON_ERROR_STOP=1 \
  --dbname="$DATABASE_URL" -c "select current_setting('\''server_version_num'\'')::int / 10000"')"
if [ "$server_major" != "17" ]; then
  echo "Staging dump requires PostgreSQL 17, found major version: $server_major" >&2
  exit 1
fi

run_postgres bash -o pipefail -ceu '
pg_dumpall --dbname="$DATABASE_URL" --roles-only --role postgres \
  --quote-all-identifier --no-role-passwords --no-comments \
| sed -E "s/^\\\\(un)?restrict .*$/-- &/" \
| sed -E "s/^CREATE ROLE \"(anon|authenticated|authenticator|cli_login_.*|dashboard_user|pgbouncer|postgres|service_role|supabase_.*|pgsodium_keyholder|pgsodium_keyiduser|pgsodium_keymaker|pgtle_admin)\"/-- &/" \
| sed -E "s/^ALTER ROLE \"(anon|authenticated|authenticator|cli_login_.*|dashboard_user|pgbouncer|postgres|service_role|supabase_.*|pgsodium_keyholder|pgsodium_keyiduser|pgsodium_keymaker|pgtle_admin)\"/-- &/" \
| sed -E "s/ (NOSUPERUSER|NOREPLICATION)//g" \
| sed -E "s/^-- (.* SET \"(pgaudit.*|pgrst.*|session_replication_role|statement_timeout|track_io_timing)\" .*)/\\1/" \
| sed -E "s/GRANT \".*\" TO \"(anon|authenticated|authenticator|cli_login_.*|dashboard_user|pgbouncer|postgres|service_role|supabase_.*|pgsodium_keyholder|pgsodium_keyiduser|pgsodium_keymaker|pgtle_admin)\"/-- &/" \
| sed -E "/^--/d" \
| uniq
echo "RESET ALL;"
' > "$output_dir/roles.sql"

run_postgres bash -o pipefail -ceu '
pg_dump --dbname="$DATABASE_URL" --schema-only --quote-all-identifier --role postgres \
  --exclude-schema "information_schema|pg_*|_analytics|_realtime|_supavisor|auth|etl|extensions|pgbouncer|realtime|storage|supabase_functions|supabase_migrations|cron|dbdev|graphql|graphql_public|net|pgmq|pgsodium|pgsodium_masks|pgtle|repack|tiger|tiger_data|timescaledb_*|_timescaledb_*|topology|vault" \
| sed -E "s/^\\\\(un)?restrict .*$/-- &/" \
| sed -E "s/^CREATE SCHEMA \"/CREATE SCHEMA IF NOT EXISTS \"/" \
| sed -E "s/^CREATE TABLE \"/CREATE TABLE IF NOT EXISTS \"/" \
| sed -E "s/^CREATE SEQUENCE \"/CREATE SEQUENCE IF NOT EXISTS \"/" \
| sed -E "s/^CREATE VIEW \"/CREATE OR REPLACE VIEW \"/" \
| sed -E "s/^CREATE FUNCTION \"/CREATE OR REPLACE FUNCTION \"/" \
| sed -E "s/^CREATE TRIGGER \"/CREATE OR REPLACE TRIGGER \"/" \
| sed -E "s/^CREATE PUBLICATION \"supabase_realtime/-- &/" \
| sed -E "s/^CREATE EVENT TRIGGER /-- &/" \
| sed -E "s/^         WHEN TAG IN /-- &/" \
| sed -E "s/^   EXECUTE FUNCTION /-- &/" \
| sed -E "s/^ALTER EVENT TRIGGER /-- &/" \
| sed -E "s/^ALTER PUBLICATION \"supabase_realtime_/-- &/" \
| sed -E "s/^ALTER FOREIGN DATA WRAPPER (.+) OWNER TO /-- &/" \
| sed -E "s/^ALTER DEFAULT PRIVILEGES FOR ROLE \"supabase_admin\"/-- &/" \
| sed -E "s/^GRANT ALL ON FOREIGN DATA WRAPPER (.+) TO \"postgres\" WITH GRANT OPTION/-- &/" \
| sed -E "s/^GRANT (.+) ON (.+) \"(information_schema|pg_*|_analytics|_realtime|_supavisor|auth|etl|extensions|pgbouncer|realtime|storage|supabase_functions|supabase_migrations|cron|dbdev|graphql|graphql_public|net|pgmq|pgsodium|pgsodium_masks|pgtle|repack|tiger|tiger_data|timescaledb_*|_timescaledb_*|topology|vault)\"/-- &/" \
| sed -E "s/^REVOKE (.+) ON (.+) \"(information_schema|pg_*|_analytics|_realtime|_supavisor|auth|etl|extensions|pgbouncer|realtime|storage|supabase_functions|supabase_migrations|cron|dbdev|graphql|graphql_public|net|pgmq|pgsodium|pgsodium_masks|pgtle|repack|tiger|tiger_data|timescaledb_*|_timescaledb_*|topology|vault)\"/-- &/" \
| sed -E "s/^(CREATE EXTENSION IF NOT EXISTS \"pg_tle\").+/\\1;/" \
| sed -E "s/^(CREATE EXTENSION IF NOT EXISTS \"pgsodium\").+/\\1;/" \
| sed -E "s/^(CREATE EXTENSION IF NOT EXISTS \"pgmq\").+/\\1;/" \
| sed -E "s/^COMMENT ON EXTENSION (.+)/-- &/" \
| sed -E "s/^CREATE POLICY \"cron_job_/-- &/" \
| sed -E "s/^ALTER TABLE \"cron\"/-- &/" \
| sed -E "s/^SET transaction_timeout = 0;/-- &/" \
| sed -E "/^--/d"
' > "$output_dir/schema.sql"

run_postgres bash -o pipefail -ceu '
printf "SET session_replication_role = replica;\\n\\n"
pg_dump --dbname="$DATABASE_URL" --data-only --quote-all-identifier --role postgres \
  --exclude-schema "information_schema|pg_*|graphql|graphql_public|pgsodium|pgsodium_masks|pgtle|repack|tiger|tiger_data|timescaledb_*|_timescaledb_*|topology|vault|etl|extensions|pgbouncer|realtime|supabase_migrations|_analytics|_realtime|_supavisor" \
  --exclude-table "auth.schema_migrations" \
  --exclude-table "storage.migrations" \
  --exclude-table "supabase_functions.migrations" \
  --exclude-table "storage.buckets_vectors" \
  --exclude-table "storage.vector_indexes" \
  --schema "*" \
| sed -E "s/^\\\\(un)?restrict .*$/-- &/"
echo "RESET ALL;"
' > "$output_dir/data.sql"

run_postgres bash -o pipefail -ceu '
pg_dump --dbname="$DATABASE_URL" --schema-only --quote-all-identifier --role postgres \
  --schema supabase_migrations \
| sed -E "s/^\\\\(un)?restrict .*$/-- &/" \
| sed -E "s/^CREATE SCHEMA \"/CREATE SCHEMA IF NOT EXISTS \"/" \
| sed -E "s/^CREATE TABLE \"/CREATE TABLE IF NOT EXISTS \"/" \
| sed -E "s/^CREATE SEQUENCE \"/CREATE SEQUENCE IF NOT EXISTS \"/" \
| sed -E "s/^CREATE VIEW \"/CREATE OR REPLACE VIEW \"/" \
| sed -E "s/^CREATE FUNCTION \"/CREATE OR REPLACE FUNCTION \"/" \
| sed -E "s/^CREATE TRIGGER \"/CREATE OR REPLACE TRIGGER \"/" \
| sed -E "s/^SET transaction_timeout = 0;/-- &/" \
| sed -E "/^--/d"
' > "$output_dir/migration-schema.sql"

run_postgres bash -o pipefail -ceu '
printf "SET session_replication_role = replica;\\n\\n"
pg_dump --dbname="$DATABASE_URL" --data-only --quote-all-identifier --role postgres \
  --schema supabase_migrations \
| sed -E "s/^\\\\(un)?restrict .*$/-- &/"
echo "RESET ALL;"
' > "$output_dir/migration-history.sql"
