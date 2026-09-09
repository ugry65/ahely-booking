#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"
marker_file="${4:-.github/staging-backup-drill.trigger}"

if [ "$ref_name" != "staging" ]; then
  echo "This drill may run only from the staging branch." >&2
  exit 1
fi

case "$event_name" in
  workflow_dispatch)
    if [ "$confirmation" != "STAGING-BACKUP" ]; then
      echo "Staging backup drill requires confirmation input: STAGING-BACKUP" >&2
      exit 1
    fi
    ;;
  push)
    marker=""
    if [ -f "$marker_file" ]; then
      IFS= read -r marker < "$marker_file" || true
    fi
    if [ "$marker" != "STAGING-BACKUP" ]; then
      echo "Staging backup drill trigger marker is missing or invalid." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported staging backup drill event: $event_name" >&2
    exit 1
    ;;
esac
