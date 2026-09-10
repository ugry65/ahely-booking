#!/usr/bin/env bash
set -Eeuo pipefail

test_dir="$(mktemp -d)"
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

mock_bin="$test_dir/bin"
remote_dir="$test_dir/remotes"
mkdir -p "$mock_bin" "$remote_dir"

cat > "$mock_bin/psql" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == *"show server_version_num"* ]]; then
  printf '170006\n'
else
  printf '{"auth_users":0,"profiles":0,"bookings_total":0}\n'
fi
MOCK

cat > "$mock_bin/supabase" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [ "$1" != "--workdir" ]; then
  echo "Missing isolated Supabase workdir" >&2
  exit 1
fi
grep -qx 'major_version = 17' "$2/supabase/config.toml"
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-f" ]; then output="$2"; break; fi
  shift
done
[ -n "$output" ]
printf '%s\n' '-- non-empty test dump' > "$output"
MOCK

cat > "$mock_bin/age" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" > "$MOCK_AGE_LOG"
output=""
input=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --recipient) shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) input="$1"; shift ;;
  esac
done
cp "$input" "$output"
MOCK

cat > "$mock_bin/rclone" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
command_name="$1"
shift
map_remote() {
  printf '%s/%s' "$MOCK_REMOTE_DIR" "${1/:/\/}"
}
if [ "$command_name" = "copyto" ]; then
  source_file="$1"
  destination="$(map_remote "$2")"
  mkdir -p "$(dirname "$destination")"
  cp "$source_file" "$destination"
elif [ "$command_name" = "cat" ]; then
  cat "$(map_remote "$1")"
else
  exit 1
fi
MOCK

chmod +x "$mock_bin/psql" "$mock_bin/supabase" "$mock_bin/age" "$mock_bin/rclone"

output="$({
  PATH="$mock_bin:$PATH" \
  MOCK_REMOTE_DIR="$remote_dir" \
  MOCK_AGE_LOG="$test_dir/age.log" \
  PRODUCTION_DB_URL='postgresql://postgres:secret@db.yasrmxwjojepessivhmc.supabase.co:5432/postgres' \
  PRODUCTION_DRILL_AGE_RECIPIENT='age1productiontest' \
  BACKUP_GDRIVE_REMOTE='gdrive:backups' \
  BACKUP_B2_REMOTE='b2:backups' \
  GITHUB_SHA='0123456789abcdef0123456789abcdef01234567' \
  bash ./scripts/backup-production-drill.sh
} 2>&1)"

grep -q 'PRODUCTION DRILL backup verified on both targets' <<< "$output"
grep -q 'CONTROL_COUNTS=' <<< "$output"
test "$(grep -o -- '--recipient' "$test_dir/age.log" | wc -l)" -eq 1
grep -q -- '--recipient age1test --recipient age1stagingtest' "$test_dir/age.log"
test "$(find "$remote_dir" -type f -name '*.tar.gz.age' | wc -l)" -eq 2
test "$(find "$remote_dir" -type f -name '*.tar.gz.age.sha256' | wc -l)" -eq 2
test "$(find "$remote_dir" -type f -name '*.tar.gz' | wc -l)" -eq 0
test "$(find "$remote_dir" -type f | grep -vc '/production-drill/' || true)" -eq 0
grep -qx 'major_version = 15' supabase/config.toml

echo "Production backup drill pipeline tests passed"
