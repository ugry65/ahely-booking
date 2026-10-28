#!/usr/bin/env bash
set -Eeuo pipefail
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export TEST_STATE="$work" TEST_CASE=success
export PATH="$work/bin:$PATH"
export GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF_NAME=main
export PRODUCTION_DB_URL=postgresql://postgres:synthetic@db.yasrmxwjojepessivhmc.supabase.co/postgres
cat > "$work/bin/psql" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
q="${*: -1}"
if [[ "$q" == *string_agg* ]]; then
  if [ "$TEST_CASE" = changed-history ]; then echo '94|changed'; else echo '94|9d7fb2c6810f325a6a5fc6097c6d472f'; fi
elif [[ "$q" == *'select version from'* ]]; then
  seq 20260000000001 20260000000094
elif [[ "$q" == *'md5(prosrc)'* ]]; then
  if [ "$TEST_CASE" = changed-function ]; then echo 'wrong|{postgres=X/postgres}'
  elif [ -e "$TEST_STATE/applied" ]; then echo '1f81f5938e5aefdf195f0f38ab4600c4|{postgres=X/postgres}'
  else echo 'd2fec9704285eeb0706bcd4e5d369b4a|{postgres=X/postgres}'; fi
elif [ -e "$TEST_STATE/applied" ] || [ "$TEST_CASE" = replay ]; then echo 1
else echo 0; fi
MOCK
cat > "$work/bin/supabase" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
args="$*"
[[ "$args" != *--include-all* && "$args" != *repair* && "$args" != *--include-seed* && "$args" != *--include-roles* ]]
[ "$1" = --workdir ]; dir="$2"; shift 2
if [ "$1 $2" = 'migration fetch' ]; then
  for v in $(seq 20260000000001 20260000000094); do echo '-- already applied' > "$dir/supabase/migrations/${v}_old.sql"; done
  if [ "$TEST_CASE" = missing-fetch ]; then rm "$dir/supabase/migrations/20260000000001_old.sql"; fi
else
  [[ "$args" == *--skip-vault* ]]
  if [[ "$args" == *--dry-run* ]]; then
    echo 'Would push these migrations:'
    echo '20261028151000_training_group_180_day_limit.sql'
    if [ "$TEST_CASE" = historical-plan ]; then echo '20260000000001_old.sql'; fi
  else touch "$TEST_STATE/applied"; fi
fi
MOCK
chmod +x "$work/bin/psql" "$work/bin/supabase"
fail_case() {
  rm -f "$TEST_STATE/applied"
  if bash scripts/deploy-training-group-316.sh "${1:-dry-run}"; then echo "Expected $TEST_CASE rejection" >&2; exit 1; fi
  test ! -e "$TEST_STATE/applied"
}
bash scripts/deploy-training-group-316.sh dry-run
test ! -e "$TEST_STATE/applied"
for TEST_CASE in changed-history changed-function replay missing-fetch historical-plan; do export TEST_CASE; fail_case; done
export TEST_CASE=success CONFIRMATION=wrong
fail_case deploy
GITHUB_REF_NAME=feature fail_case
export CONFIRMATION=PRODUCTION-20261028151000
bash scripts/deploy-training-group-316.sh deploy
test -e "$TEST_STATE/applied"
echo 'targeted production migration orchestration tests PASS'
