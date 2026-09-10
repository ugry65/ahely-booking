#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"
artifact="${4:-}"

if [ "$ref_name" != "main" ]; then
  echo "Production restore drill may run only from main." >&2
  exit 1
fi
if [ "$event_name" != "workflow_dispatch" ]; then
  echo "Production restore drill requires an explicit workflow_dispatch event." >&2
  exit 1
fi
if [ "$confirmation" != "RESTORE-PRODUCTION" ]; then
  echo "Production restore drill requires confirmation: RESTORE-PRODUCTION" >&2
  exit 1
fi
if [[ "$artifact" =~ / ]] ||
  [[ ! "$artifact" =~ ^ahely-booking-production-drill_[0-9]{8}T[0-9]{6}Z_[0-9a-f]{12}\.tar\.gz\.age$ ]]; then
  echo "Invalid production restore artifact name" >&2
  exit 1
fi
