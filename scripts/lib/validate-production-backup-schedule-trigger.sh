#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"
event_schedule="${4:-}"

if [ "$ref_name" != "main" ]; then
  echo "Production backup may run only from main." >&2
  exit 1
fi

case "$event_name" in
  workflow_dispatch)
    if [ "$confirmation" != "BACKUP" ]; then
      echo "Manual production backup requires confirmation: BACKUP" >&2
      exit 1
    fi
    printf '%s\n' "manual"
    ;;
  schedule)
    case "$event_schedule" in
      "0 8 * * *") printf '%s\n' "08" ;;
      "0 12 * * *") printf '%s\n' "12" ;;
      "0 16 * * *") printf '%s\n' "16" ;;
      "0 20 * * *") printf '%s\n' "20" ;;
      *)
        echo "Unknown production backup schedule." >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported production backup event: $event_name" >&2
    exit 1
    ;;
esac
