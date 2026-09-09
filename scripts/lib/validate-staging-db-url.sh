#!/usr/bin/env bash
set -Eeuo pipefail

readonly AHELY_STAGING_PROJECT_REF="fvwapntzhavhgazeflri"

validate_staging_db_url() {
  local database_url="${1:-}"

  python3 - "$database_url" "$AHELY_STAGING_PROJECT_REF" <<'PY'
import sys
from urllib.parse import urlparse

database_url, expected_ref = sys.argv[1:]

try:
    parsed = urlparse(database_url)
    hostname = (parsed.hostname or "").lower()
    username = parsed.username or ""
except ValueError:
    hostname = ""
    username = ""

valid_scheme = parsed.scheme in {"postgres", "postgresql"} if "parsed" in locals() else False
is_direct = hostname == f"db.{expected_ref}.supabase.co"
is_pooler = username == f"postgres.{expected_ref}" and hostname.endswith(".pooler.supabase.com")

if not (valid_scheme and (is_direct or is_pooler)):
    print(
        "STAGING_DB_URL does not identify the approved A-Hely staging project; refusing to continue.",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  validate_staging_db_url "${1:-}"
fi
