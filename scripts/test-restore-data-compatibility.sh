#!/usr/bin/env bash
set -Eeuo pipefail
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cat >"$work/target.tsv" <<'EOF'
auth.users	id,email
public.bookings	id,status
EOF
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
python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/in.sql" --output "$work/out.sql" --target-columns "$work/target.tsv"
grep -q 'COPY auth.users' "$work/out.sql"
! grep -q 'mfa_recovery_code_sets' "$work/out.sql"
grep -q 'COPY public.bookings' "$work/out.sql"

cat >"$work/bad.sql" <<'EOF'
COPY auth.new_table (id) FROM stdin;
1
\.
EOF
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/bad.sql" --output "$work/bad-out.sql" --target-columns "$work/target.tsv"; then
  echo "Expected non-empty incompatible managed table to fail" >&2; exit 1
fi
cat >"$work/public-empty.sql" <<'EOF'
COPY public.unknown (id) FROM stdin;
\.
EOF
if python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/public-empty.sql" --output "$work/public-out.sql" --target-columns "$work/target.tsv"; then
  echo "Expected incompatible public table to fail even when empty" >&2; exit 1
fi
cat >"$work/target-tab.tsv" <<\'EOF\'
auth.users\tid,email
public.bookings\tid,status
EOF
python3 scripts/lib/prepare-supabase-restore-data.py --input "$work/in.sql" --output "$work/out-tab.sql" --target-columns "$work/target-tab.tsv"
grep -q \'COPY auth.users\' "$work/out-tab.sql"
! grep -q \'mfa_recovery_code_sets\' "$work/out-tab.sql"

echo "restore data compatibility tests PASS"
