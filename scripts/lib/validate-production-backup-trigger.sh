#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"

if [ "$ref_name" != "main" ]; then
  echo "Production backup drill may run only from main." >&2
  exit 1
fi

if [ "$event_name" != "workflow_dispatch" ]; then
  echo "Production backup drill supports manual dispatch only." >&2
  exit 1
fi

if [ "$confirmation" != "PRODUCTION-BACKUP" ]; then
  echo "Production backup drill requires confirmation: PRODUCTION-BACKUP" >&2
  exit 1
fi
