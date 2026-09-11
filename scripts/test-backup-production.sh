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
  printf '{"auth_users":12,"profiles":12,"bookings_total":87,"migration_history_rows":42}\n'
fi
MOCK

cat > "$mock_bin/supabase" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [ "${1:-}" = "--version" ]; then
  printf '2.116.0\n'
  exit 0
fi
if [ "${1:-}" != "--workdir" ]; then
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
map_remote() { printf '%s/%s' "$MOCK_REMOTE_DIR" "${1/:/\/}"; }
case "$command_name" in
  copyto)
    source_file="$1"
    destination="$2"
    if [[ "$destination" == b2:* ]] && [ "${FAIL_B2_UPLOAD:-0}" = "1" ]; then
      echo "Simulated B2 upload failure" >&2
      exit 23
    fi
    target="$(map_remote "$destination")"
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
    ;;
  cat) cat "$(map_remote "$1")" ;;
  *) exit 1 ;;
esac
MOCK

chmod +x "$mock_bin/psql" "$mock_bin/supabase" "$mock_bin/age" "$mock_bin/rclone"

run_backup() {
  PATH="$mock_bin:$PATH" \
  MOCK_REMOTE_DIR="$1" \
  FAIL_B2_UPLOAD="${2:-0}" \
  PRODUCTION_DB_URL='postgresql://postgres:secret@db.yasrmxwjojepessivhmc.supabase.co:5432/postgres' \
  BACKUP_AGE_RECIPIENT='age1productiontest' \
  BACKUP_GDRIVE_REMOTE='gdrive:backups' \
  BACKUP_B2_REMOTE='b2:backups' \
  GITHUB_SHA='0123456789abcdef0123456789abcdef01234567' \
  bash ./scripts/backup-production.sh
}

output="$(run_backup "$remote_dir")"
grep -q 'Backup artifact verified on both independent targets' <<< "$output"

mapfile -t encrypted_artifacts < <(find "$remote_dir" -type f -name '*.tar.gz.age' | sort)
test "${#encrypted_artifacts[@]}" -eq 2
test "$(find "$remote_dir" -type f -name '*.tar.gz.age.sha256' | wc -l)" -eq 2
test "$(find "$remote_dir" -type f -name '*.tar.gz' | wc -l)" -eq 0
test "$(sha256sum "${encrypted_artifacts[0]}" | awk '{print $1}')" = \
  "$(sha256sum "${encrypted_artifacts[1]}" | awk '{print $1}')"
grep -qx 'major_version = 15' supabase/config.toml

failure_remote_dir="$test_dir/remotes-failure"
mkdir -p "$failure_remote_dir"
if run_backup "$failure_remote_dir" 1 >/dev/null 2>&1; then
  echo "Backup unexpectedly succeeded after simulated B2 failure" >&2
  exit 1
fi
if ! find "$failure_remote_dir/gdrive" -type f -name '*.tar.gz.age' -print -quit | grep -q .; then
  echo "Expected failure scenario to reach Drive before B2 failure" >&2
  exit 1
fi

echo "Production backup pipeline tests passed"
