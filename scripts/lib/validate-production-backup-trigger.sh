#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"
marker_file="${4:-.github/production-backup-drill.trigger}"

if [ "$ref_name" != "main" ]; then
  echo "Production backup drill may run only from main." >&2
  exit 1
fi

case "$event_name" in
  workflow_dispatch)
    if [ "$confirmation" != "PRODUCTION-BACKUP" ]; then
      echo "Production backup drill requires confirmation: PRODUCTION-BACKUP" >&2
      exit 1
    fi
    ;;
  push)
    marker=""
    if [ -f "$marker_file" ]; then
      IFS= read -r marker < "$marker_file" || true
    fi
    if [ "$marker" != "PRODUCTION-BACKUP" ]; then
      echo "Production backup drill trigger marker is missing or invalid." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported production backup drill event: $event_name" >&2
    exit 1
    ;;
esac
