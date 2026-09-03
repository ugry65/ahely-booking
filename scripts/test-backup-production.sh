#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT

fake_bin="$test_root/bin"
remote_root="$test_root/remotes"
mkdir -p "$fake_bin" "$remote_root"

cat > "$fake_bin/supabase" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [ "${1:-}" = "--version" ]; then
  echo "2.114.0"
  exit 0
fi
if [ "${1:-}" != "db" ] || [ "${2:-}" != "dump" ]; then
  echo "Unexpected supabase command" >&2
  exit 1
fi
output=""
shift 2
while [ "$#" -gt 0 ]; do
  case "$1" in
    -f)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [ -z "$output" ]; then
  echo "Missing fake dump output" >&2
  exit 1
fi
printf '%s\n' '-- fake Supabase backup content' 'select 1;' > "$output"
EOF
chmod +x "$fake_bin/supabase"

cat > "$fake_bin/psql" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cat <<'JSON'
{"auth_users":12,"profiles":12,"rooms":9,"user_room_permissions":21,"booking_series":4,"bookings_total":87,"bookings_active":80,"bookings_cancelled":7,"booking_cancellations":7,"audit_logs":154,"monthly_settlements":10,"settlement_revisions":13,"settlement_booking_lines":75}
JSON
EOF
chmod +x "$fake_bin/psql"

cat > "$fake_bin/age" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
output=""
source_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --recipient)
      shift 2
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    *)
      source_file="$1"
      shift
      ;;
  esac
done
if [ -z "$output" ] || [ -z "$source_file" ]; then
  echo "Invalid fake age invocation" >&2
  exit 1
fi
cp "$source_file" "$output"
EOF
chmod +x "$fake_bin/age"

cat > "$fake_bin/rclone" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
command_name="${1:-}"
shift || true
remote_path() {
  local remote="$1"
  local provider="${remote%%:*}"
  local path="${remote#*:}"
  printf '%s/%s/%s' "$FAKE_RCLONE_ROOT" "$provider" "$path"
}
case "$command_name" in
  copyto)
    source_file="$1"
    destination="$2"
    if [[ "$destination" == b2:* ]] && [ "${FAIL_B2_UPLOAD:-0}" = "1" ]; then
      echo "Simulated B2 upload failure" >&2
      exit 23
    fi
    target="$(remote_path "$destination")"
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
    ;;
  cat)
    source_remote="$1"
    cat "$(remote_path "$source_remote")"
    ;;
  *)
    echo "Unexpected fake rclone command: $command_name" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_bin/rclone"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
url="${*: -1}"
printf '%s\n' "$url" >> "$FAKE_HEARTBEAT_LOG"
EOF
chmod +x "$fake_bin/curl"

export PATH="$fake_bin:$PATH"
export FAKE_RCLONE_ROOT="$remote_root"
export PRODUCTION_DB_URL="postgresql://example.invalid/postgres"
export BACKUP_AGE_RECIPIENT="age1testrecipient"
export BACKUP_GDRIVE_REMOTE="gdrive:A-Hely-Booking-Backups"
export BACKUP_B2_REMOTE="b2:ahely-booking-production-backups"
export GITHUB_SHA="1234567890abcdef1234567890abcdef12345678"

success_heartbeat_log="$test_root/heartbeat-success.log"
export FAKE_HEARTBEAT_LOG="$success_heartbeat_log"
export BACKUP_HEARTBEAT_URL="https://heartbeat.example.invalid/backup-08"

bash "$repo_root/scripts/backup-production.sh"

mapfile -t gdrive_artifacts < <(find "$remote_root/gdrive" -type f -name '*.tar.gz.age' | sort)
mapfile -t b2_artifacts < <(find "$remote_root/b2" -type f -name '*.tar.gz.age' | sort)

if [ "${#gdrive_artifacts[@]}" -ne 1 ] || [ "${#b2_artifacts[@]}" -ne 1 ]; then
  echo "Expected exactly one encrypted artifact on each remote" >&2
  exit 1
fi

if [ "$(sha256sum "${gdrive_artifacts[0]}" | awk '{print $1}')" != "$(sha256sum "${b2_artifacts[0]}" | awk '{print $1}')" ]; then
  echo "Encrypted artifacts differ between independent targets" >&2
  exit 1
fi

if ! grep -Fxq "$BACKUP_HEARTBEAT_URL" "$success_heartbeat_log"; then
  echo "Success heartbeat was not sent after verified dual upload" >&2
  exit 1
fi

failure_remote_root="$test_root/remotes-failure"
mkdir -p "$failure_remote_root"
export FAKE_RCLONE_ROOT="$failure_remote_root"
failure_heartbeat_log="$test_root/heartbeat-failure.log"
export FAKE_HEARTBEAT_LOG="$failure_heartbeat_log"
export FAIL_B2_UPLOAD=1

if bash "$repo_root/scripts/backup-production.sh"; then
  echo "Backup unexpectedly succeeded when B2 upload was forced to fail" >&2
  exit 1
fi

if [ -s "$failure_heartbeat_log" ]; then
  echo "Success heartbeat must not be sent after partial backup failure" >&2
  exit 1
fi

if ! find "$failure_remote_root/gdrive" -type f -name '*.tar.gz.age' -print -quit | grep -q .; then
  echo "Expected the failure scenario to reach the first target before B2 failure" >&2
  exit 1
fi

printf '%s\n' "Backup pipeline integration tests passed."
