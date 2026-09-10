#!/usr/bin/env bash
set -Eeuo pipefail

readonly AHELY_PRODUCTION_PROJECT_REF="yasrmxwjojepessivhmc"

python3 - "${1:-}" "$AHELY_PRODUCTION_PROJECT_REF" <<'PY'
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
    print("PRODUCTION_DB_URL does not identify the approved A-Hely production project; refusing to continue.", file=sys.stderr)
    raise SystemExit(1)
PY
