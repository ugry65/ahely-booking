#!/usr/bin/env bash
set -Eeuo pipefail
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat >"$work/in.sql" <<'EOF'
COPY auth.users (id, email) FROM stdin;
1	a@example.com
\.
COPY auth.mfa_recovery_code_sets (id) FROM stdin;
\.
COPY public.bookings (id, status) FROM stdin;
1	active
\.
EOF

# Exact format emitted by restore-production-drill.sh: psql -F "|".
cat >"$work/target-pipe.txt" <<'EOF'
auth.users|id,email
public.bookings|id,status
EOF
python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/in.sql" --output "$work/out-pipe.sql" --target-columns "$work/target-pipe.txt"
grep -q 'COPY auth.users' "$work/out-pipe.sql"
! grep -q 'mfa_recovery_code_sets' "$work/out-pipe.sql"
grep -q 'COPY public.bookings' "$work/out-pipe.sql"

# Backward-compatible parser coverage for tab-separated schema snapshots.
printf 'auth.users\tid,email\npublic.bookings\tid,status\n' >"$work/target-tab.txt"
python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/in.sql" --output "$work/out-tab.sql" --target-columns "$work/target-tab.txt"
grep -q 'COPY auth.users' "$work/out-tab.sql"
! grep -q 'mfa_recovery_code_sets' "$work/out-tab.sql"

cat >"$work/bad.sql" <<'EOF'
COPY auth.new_table (id) FROM stdin;
1
\.
EOF
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/bad.sql" --output "$work/bad-out.sql" --target-columns "$work/target-pipe.txt"; then
  echo "Expected non-empty incompatible managed table to fail" >&2
  exit 1
fi

cat >"$work/public-empty.sql" <<'EOF'
COPY public.unknown (id) FROM stdin;
\.
EOF
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/public-empty.sql" --output "$work/public-out.sql" --target-columns "$work/target-pipe.txt"; then
  echo "Expected incompatible public table to fail even when empty" >&2
  exit 1
fi

printf 'invalid-row-without-delimiter\n' >"$work/invalid-target.txt"
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/in.sql" --output "$work/invalid-out.sql" --target-columns "$work/invalid-target.txt"; then
  echo "Expected malformed target schema row to fail" >&2
  exit 1
fi

echo "restore data compatibility tests PASS"

# The production failure contained a non-empty Auth expiry column. It must
# fail on the old target and survive byte-for-byte on a compatible target.
cat >"$work/token.sql" <<'EOF'
COPY auth.one_time_tokens (id, expires_at) FROM stdin;
1	2026-10-28 19:00:00+00
\.
EOF
printf 'auth.one_time_tokens|id\n' >"$work/old-auth.txt"
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/token.sql" --output "$work/token-old.sql" --target-columns "$work/old-auth.txt"; then
  echo "Expected non-empty expiry data to fail on old Auth schema" >&2
  exit 1
fi
printf 'auth.one_time_tokens|id,expires_at\n' >"$work/new-auth.txt"
python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/token.sql" --output "$work/token-new.sql" --target-columns "$work/new-auth.txt"
cmp "$work/token.sql" "$work/token-new.sql"
