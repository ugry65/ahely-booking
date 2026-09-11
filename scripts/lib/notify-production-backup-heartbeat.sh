#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:-}"
slot="${2:-}"

case "$slot" in
  08) heartbeat_url="${BACKUP_HEARTBEAT_08_URL:-}" ;;
  12) heartbeat_url="${BACKUP_HEARTBEAT_12_URL:-}" ;;
  16) heartbeat_url="${BACKUP_HEARTBEAT_16_URL:-}" ;;
  20) heartbeat_url="${BACKUP_HEARTBEAT_20_URL:-}" ;;
  *)
    echo "Invalid production backup heartbeat slot." >&2
    exit 1
    ;;
esac

if [[ "$heartbeat_url" != https://* ]]; then
  echo "Missing or non-HTTPS production backup heartbeat URL for slot $slot." >&2
  exit 1
fi

case "$action" in
  start) endpoint="${heartbeat_url%/}/start" ;;
  success) endpoint="${heartbeat_url%/}" ;;
  fail) endpoint="${heartbeat_url%/}/fail" ;;
  *)
    echo "Invalid production backup heartbeat action." >&2
    exit 1
    ;;
esac

curl --silent --show-error --fail --max-time 20 --retry 2 --output /dev/null "$endpoint"
printf 'Production backup heartbeat acknowledged: slot=%s action=%s\n' "$slot" "$action"
