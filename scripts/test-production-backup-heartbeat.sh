#!/usr/bin/env bash
set -Eeuo pipefail

test_dir="$(mktemp -d)"
cleanup() { rm -rf "$test_dir"; }
trap cleanup EXIT

mkdir -p "$test_dir/bin"
cat > "$test_dir/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${*: -1}" >> "$MOCK_HEARTBEAT_LOG"
MOCK
chmod +x "$test_dir/bin/curl"

export PATH="$test_dir/bin:$PATH"
export MOCK_HEARTBEAT_LOG="$test_dir/heartbeat.log"
export BACKUP_HEARTBEAT_08_URL="https://hc-ping.example/slot-08"
export BACKUP_HEARTBEAT_12_URL="https://hc-ping.example/slot-12/"
export BACKUP_HEARTBEAT_16_URL="https://hc-ping.example/slot-16"
export BACKUP_HEARTBEAT_20_URL="https://hc-ping.example/slot-20"

bash ./scripts/lib/notify-production-backup-heartbeat.sh start 08
bash ./scripts/lib/notify-production-backup-heartbeat.sh success 12
bash ./scripts/lib/notify-production-backup-heartbeat.sh fail 20

grep -Fxq 'https://hc-ping.example/slot-08/start' "$MOCK_HEARTBEAT_LOG"
grep -Fxq 'https://hc-ping.example/slot-12' "$MOCK_HEARTBEAT_LOG"
grep -Fxq 'https://hc-ping.example/slot-20/fail' "$MOCK_HEARTBEAT_LOG"

if BACKUP_HEARTBEAT_16_URL='http://insecure.example/slot-16' \
  bash ./scripts/lib/notify-production-backup-heartbeat.sh success 16 >/dev/null 2>&1; then
  echo "Non-HTTPS heartbeat URL unexpectedly passed" >&2
  exit 1
fi
if bash ./scripts/lib/notify-production-backup-heartbeat.sh success manual >/dev/null 2>&1; then
  echo "Invalid heartbeat slot unexpectedly passed" >&2
  exit 1
fi

echo "Production backup heartbeat tests passed"
