#!/usr/bin/env bash
set -Eeuo pipefail
# This test creates disposable fixtures, never a hosted or application DB.
if [ "${PGHOST:-}" != "127.0.0.1" ] || [ "${PGDATABASE:-}" != "restore_compat_test" ]; then
  echo "Requires loopback-only restore_compat_test database" >&2
  exit 1
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
create schema auth;
create table auth.one_time_tokens(id integer primary key, token_hash text not null);
insert into auth.one_time_tokens values (1, 'synthetic-token-hash');
SQL
psql -X -v ON_ERROR_STOP=1 -f "$script_dir/lib/prepare-isolated-auth-restore.sql"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
update auth.one_time_tokens set expires_at = '2026-10-28 19:00:00+00';
SQL
psql -X -v ON_ERROR_STOP=1 -f "$script_dir/lib/prepare-isolated-auth-restore.sql"
psql -X -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if (select count(*) from auth.one_time_tokens) <> 1 or not exists (
    select 1 from auth.one_time_tokens where id = 1
      and token_hash = 'synthetic-token-hash'
      and expires_at = '2026-10-28 19:00:00+00'::timestamptz
  ) then raise exception 'Compatibility preparation changed existing token data'; end if;
end $$;
alter table auth.one_time_tokens alter column expires_at type text;
SQL
if psql -X -v ON_ERROR_STOP=1 -f "$script_dir/lib/prepare-isolated-auth-restore.sql"; then
  echo "Expected wrong existing expires_at type to fail closed" >&2
  exit 1
fi
echo "isolated Auth restore schema tests PASS"
