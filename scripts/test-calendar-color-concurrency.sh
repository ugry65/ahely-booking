#!/usr/bin/env bash
set -euo pipefail

if ! command -v psql >/dev/null 2>&1; then
  echo "Hiba: a psql kliens nincs telepítve." >&2
  exit 127
fi

readonly database_url="${AHELY_TEST_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

run_insert() {
  local suffix="$1"
  local user_id="00000000-0000-0000-0000-0000000002${suffix}"
  local output_file="$test_dir/color-${suffix}.log"
  psql "$database_url" -X -v ON_ERROR_STOP=1 >"$output_file" 2>&1 <<SQL
begin;
insert into auth.users (id, email, raw_user_meta_data)
values ('$user_id', 'color-race-${suffix}@example.invalid', '{"first_name":"Color","last_name":"Race${suffix}"}');
select pg_sleep(1);
commit;
SQL
}

pids=()
for suffix in 01 02 03 04 05; do
  run_insert "$suffix" &
  pids+=("$!")
done

set +e
failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done
set -e

if [[ "$failed" -ne 0 ]]; then
  echo "Hiba: minden párhuzamos profil-létrehozásnak sikeresnek kell lennie." >&2
  for file in "$test_dir"/*.log; do
    echo "--- $file ---" >&2
    sed -n '1,120p' "$file" >&2
  done
  exit 1
fi

read -r profile_count distinct_colors valid_colors <<<"$(
  psql "$database_url" -X -AtF' ' -v ON_ERROR_STOP=1 -c "
    select count(*), count(distinct calendar_color),
      count(*) filter (where calendar_color ~ '^#[0-9A-Fa-f]{6}$')
    from public.profiles
    where id in (
      '00000000-0000-0000-0000-000000000201',
      '00000000-0000-0000-0000-000000000202',
      '00000000-0000-0000-0000-000000000203',
      '00000000-0000-0000-0000-000000000204',
      '00000000-0000-0000-0000-000000000205'
    );
  "
)"

if [[ "$profile_count $distinct_colors $valid_colors" != "5 5 5" ]]; then
  echo "Hiba: öt párhuzamos új profilnak öt külön, érvényes színt kell kapnia." >&2
  echo "profiles=$profile_count distinct_colors=$distinct_colors valid_colors=$valid_colors" >&2
  exit 1
fi

echo "Naptárszín-konkurenciateszt sikeres: 5 párhuzamos profil 5 külön, érvényes tartós színt kapott."
