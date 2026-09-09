#!/usr/bin/env bash
set -Eeuo pipefail

event_name="${1:-}"
ref_name="${2:-}"
confirmation="${3:-}"
artifact="${4:-}"

if [ "$ref_name" != "staging" ]; then
  echo "The restore drill may run only from the staging branch" >&2
  exit 1
fi
if [ "$confirmation" != "RESTORE-STAGING" ]; then
  echo "The restore drill requires confirmation: RESTORE-STAGING" >&2
  exit 1
fi
if [ "$event_name" != "push" ] && [ "$event_name" != "workflow_dispatch" ]; then
  echo "Unsupported restore drill trigger" >&2
  exit 1
fi
if [[ "$artifact" =~ / ]] ||
  [[ ! "$artifact" =~ ^ahely-booking-staging-drill_[0-9]{8}T[0-9]{6}Z_[0-9a-f]{12}\.tar\.gz\.age$ ]]; then
  echo "Invalid staging restore artifact name" >&2
  exit 1
fi

