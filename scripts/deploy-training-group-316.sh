#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
mode="${1:-dry-run}"
if [[ "$mode" != dry-run && "$mode" != deploy ]]; then exit 1; fi
if [ "${GITHUB_EVENT_NAME:-}" != workflow_dispatch ] || [ "${GITHUB_REF_NAME:-}" != main ]; then
  echo 'Targeted production migration requires manual main workflow.' >&2; exit 1
fi
if [ "$mode" = deploy ] && [ "${CONFIRMATION:-}" != PRODUCTION-20261028151000 ]; then
  echo 'Explicit targeted production confirmation is required.' >&2; exit 1
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"
target=20261028151000_training_group_180_day_limit.sql
version=20261028151000
expected_ledger=9d7fb2c6810f325a6a5fc6097c6d472f
bash "$script_dir/lib/validate-production-db-url.sh" "${PRODUCTION_DB_URL:?}"
printf '%s  %s\n' 69f75980db82209bbb122ba3f2f50cf9c85838987a541afbb99ebe20c11d025e "$root_dir/supabase/migrations/$target" | sha256sum --check --status
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
query() { psql "$PRODUCTION_DB_URL" -X -A -t -v ON_ERROR_STOP=1 -c "$1"; }
ledger_sql="select count(*) || '|' || md5(string_agg(version || ':' || coalesce(name,'') || ':' || md5(coalesce(array_to_string(statements,''),'')), E'\\n' order by version)) from supabase_migrations.schema_migrations where version <> '$version'"
require_baseline() {
  [ "$(query "$ledger_sql")" = "94|$expected_ledger" ] || { echo 'Production migration baseline changed.' >&2; exit 1; }
  [ "$(query "select count(*) from supabase_migrations.schema_migrations where version='$version' or name='training_group_180_day_limit'")" = 0 ] || { echo 'Target migration already recorded; refusing replay.' >&2; exit 1; }
  [ "$(query "select md5(prosrc) || '|' || proacl::text from pg_proc where oid='public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure")" = 'd2fec9704285eeb0706bcd4e5d369b4a|{postgres=X/postgres}' ] || { echo 'Production function baseline changed.' >&2; exit 1; }
}
require_baseline

# Reconstruct the ALREADY APPLIED versions in an empty private workdir.
# This is a read-only fetch, never migration repair. Historical SQL must not
# be pending; only the separately pinned new migration may be added.
mkdir -p "$work/supabase/migrations"
cp "$root_dir/supabase/config.toml" "$work/supabase/config.toml"
supabase --workdir "$work" migration fetch --db-url "$PRODUCTION_DB_URL" --yes
query 'select version from supabase_migrations.schema_migrations order by version' > "$work/remote-versions"
python3 - "$work" <<'PY'
import pathlib,re,sys
w=pathlib.Path(sys.argv[1]); expected=(w/'remote-versions').read_text().splitlines()
files=list((w/'supabase/migrations').iterdir()); versions=[]
for p in files:
    m=re.fullmatch(r'([0-9]+)_[A-Za-z0-9_]+\.sql',p.name)
    if not m or p.is_symlink() or not p.is_file(): raise SystemExit('Invalid fetched migration file')
    versions.append(m[1])
if len(expected)!=94 or sorted(versions)!=sorted(expected): raise SystemExit('Fetched history differs from production versions')
PY
cp "$root_dir/supabase/migrations/$target" "$work/supabase/migrations/$target"
supabase --workdir "$work" db push --db-url "$PRODUCTION_DB_URL" --skip-vault --dry-run > "$work/plan" 2>&1
python3 - "$work/plan" "$target" <<'PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).read_text()
files=set(re.findall(r'[0-9]+_[A-Za-z0-9_]+\.sql',text))
if files!={sys.argv[2]}: raise SystemExit('Dry-run does not select exactly the approved migration')
PY
echo "Targeted migration plan verified: $target"
require_baseline
if [ "$mode" = dry-run ]; then
  echo 'DRY RUN PASS: no migrations applied.'; exit 0
fi
supabase --workdir "$work" db push --db-url "$PRODUCTION_DB_URL" --skip-vault --yes
[ "$(query "$ledger_sql")" = "94|$expected_ledger" ] || { echo 'Historical ledger changed during deploy.' >&2; exit 1; }
[ "$(query "select count(*) from supabase_migrations.schema_migrations where version='$version' and name='training_group_180_day_limit'")" = 1 ] || exit 1
[ "$(query "select md5(prosrc) || '|' || proacl::text from pg_proc where oid='public.assert_booking_request(uuid,uuid,uuid,timestamptz,timestamptz,public.booking_use_type)'::regprocedure")" = '1f81f5938e5aefdf195f0f38ab4600c4|{postgres=X/postgres}' ] || { echo 'Target function or ACL verification failed.' >&2; exit 1; }
echo 'Targeted migration PASS; original version and historical ledger preserved.'
