#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN" "$TMP_DIR/out" "$TMP_DIR/remotes/gdrive" "$TMP_DIR/remotes/b2"
printf 'synthetic booking backup fixture\n' > "$TMP_DIR/source.dump"

cat > "$MOCK_BIN/age" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
out=""
in=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --recipient) shift 2 ;;
    --output) out="$2"; shift 2 ;;
    *) in="$1"; shift ;;
  esac
done
[[ -n "$out" && -n "$in" ]]
printf 'AGE-MOCK\n' > "$out"
cat "$in" >> "$out"
SH
chmod +x "$MOCK_BIN/age"

cat > "$MOCK_BIN/rclone" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
cmd="$1"; shift
map_path() {
  case "$1" in
    gdrive:*) printf '%s/remotes/gdrive/%s' "$MOCK_ROOT" "${1#gdrive:}" ;;
    b2:*) printf '%s/remotes/b2/%s' "$MOCK_ROOT" "${1#b2:}" ;;
    *) printf '%s' "$1" ;;
  esac
}
case "$cmd" in
  copyto)
    src="$1"; dst="$(map_path "$2")"
    if [[ "${MOCK_FAIL_REMOTE:-}" != "" && "$2" == "${MOCK_FAIL_REMOTE}"* ]]; then
      exit 42
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ;;
  lsjson)
    p="$(map_path "$1")"
    [[ -f "$p" ]] || exit 44
    printf '{"Name":"%s"}\n' "$(basename "$p")"
    ;;
  *) exit 45 ;;
esac
SH
chmod +x "$MOCK_BIN/rclone"

export PATH="$MOCK_BIN:$PATH"
export MOCK_ROOT="$TMP_DIR"
export BACKUP_OUTPUT_DIR="$TMP_DIR/out"
export BACKUP_PREFIX="ahely-test"
export BACKUP_TIMESTAMP_UTC="20260831T120000Z"
export BACKUP_GIT_SHA="1234567890abcdef1234567890abcdef12345678"
export BACKUP_SOURCE_FILE="$TMP_DIR/source.dump"
export BACKUP_ALLOW_FIXTURE_SOURCE=1
export AGE_RECIPIENT="age1testrecipient"
export GDRIVE_REMOTE="gdrive:ahely"
export B2_REMOTE="b2:ahely"

output="$(bash "$ROOT_DIR/scripts/backup/create-backup.sh")"
backup_file="$(printf '%s\n' "$output" | awk -F= '/^BACKUP_FILE=/{print $2}')"
[[ -n "$backup_file" ]]
[[ -f "$TMP_DIR/remotes/gdrive/ahely/$backup_file" ]]
[[ -f "$TMP_DIR/remotes/b2/ahely/$backup_file" ]]
[[ -f "$TMP_DIR/remotes/gdrive/ahely/${backup_file}.sha256" ]]
manifest_name="${backup_file%.dump.age}.manifest.json"
[[ -f "$TMP_DIR/remotes/gdrive/ahely/$manifest_name" ]]
[[ -f "$TMP_DIR/remotes/b2/ahely/$manifest_name" ]]

python3 - "$TMP_DIR/out/$manifest_name" "$backup_file" <<'PY'
import json, sys
p, expected = sys.argv[1:]
data = json.load(open(p, encoding='utf-8'))
assert data['file'] == expected
assert data['encrypted'] is True
assert data['encryption'] == 'age'
assert data['source_kind'] == 'fixture'
assert len(data['sha256']) == 64
PY

# Fail-closed: ha a második kötelező cél hibázik, az egész futásnak hibával kell végződnie.
export BACKUP_TIMESTAMP_UTC="20260831T160000Z"
export MOCK_FAIL_REMOTE="b2:"
if bash "$ROOT_DIR/scripts/backup/create-backup.sh" >/dev/null 2>&1; then
  echo "FAIL: B2 feltöltési hiba mellett a backup script sikerrel tért vissza" >&2
  exit 1
fi

# Titkosítás kötelező valós és teszt futásban is.
unset MOCK_FAIL_REMOTE AGE_RECIPIENT
if bash "$ROOT_DIR/scripts/backup/create-backup.sh" >/dev/null 2>&1; then
  echo "FAIL: AGE_RECIPIENT nélkül a backup script sikerrel tért vissza" >&2
  exit 1
fi

echo "backup automation tests: PASS"
