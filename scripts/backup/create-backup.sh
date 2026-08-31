#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[backup] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

for cmd in sha256sum python3 age rclone; do
  command -v "$cmd" >/dev/null 2>&1 || die "Hiányzó parancs: $cmd"
done

: "${BACKUP_OUTPUT_DIR:=./backup-output}"
: "${BACKUP_PREFIX:=ahely-prod}"
: "${GDRIVE_REMOTE:?GDRIVE_REMOTE kötelező (pl. gdrive:ahely-booking-backups)}"
: "${B2_REMOTE:?B2_REMOTE kötelező (pl. b2:ahely-booking-backups)}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT kötelező; production mentés titkosítatlanul nem készülhet}"

mkdir -p "$BACKUP_OUTPUT_DIR"
chmod 700 "$BACKUP_OUTPUT_DIR"

utc_stamp="${BACKUP_TIMESTAMP_UTC:-$(date -u +%Y%m%dT%H%M%SZ)}"
git_sha="${GITHUB_SHA:-${BACKUP_GIT_SHA:-unknown}}"
base="${BACKUP_PREFIX}-${utc_stamp}-${git_sha:0:12}"
raw_path="$BACKUP_OUTPUT_DIR/${base}.dump"
enc_path="${raw_path}.age"
sha_path="${enc_path}.sha256"
manifest_path="$BACKUP_OUTPUT_DIR/${base}.manifest.json"

cleanup() {
  rm -f "$raw_path"
}
trap cleanup EXIT

if [[ -n "${BACKUP_SOURCE_FILE:-}" ]]; then
  [[ "${BACKUP_ALLOW_FIXTURE_SOURCE:-0}" == "1" ]] || die "BACKUP_SOURCE_FILE csak BACKUP_ALLOW_FIXTURE_SOURCE=1 mellett használható"
  [[ -f "$BACKUP_SOURCE_FILE" ]] || die "A tesztforrás nem létezik: $BACKUP_SOURCE_FILE"
  cp "$BACKUP_SOURCE_FILE" "$raw_path"
  source_kind="fixture"
else
  command -v pg_dump >/dev/null 2>&1 || die "Hiányzó parancs: pg_dump"
  : "${DATABASE_URL:?DATABASE_URL kötelező valós adatbázis-mentéshez}"
  source_kind="postgres"
  log "PostgreSQL logikai dump készítése"
  pg_dump \
    --dbname="$DATABASE_URL" \
    --format=custom \
    --no-owner \
    --no-privileges \
    --no-subscriptions \
    --file="$raw_path"
fi

[[ -s "$raw_path" ]] || die "A létrejött dump üres"
chmod 600 "$raw_path"

log "Kliensoldali age titkosítás"
age --recipient "$AGE_RECIPIENT" --output "$enc_path" "$raw_path"
[[ -s "$enc_path" ]] || die "A titkosított backup üres"
chmod 600 "$enc_path"
rm -f "$raw_path"

encrypted_sha="$(sha256sum "$enc_path" | awk '{print $1}')"
printf '%s  %s\n' "$encrypted_sha" "$(basename "$enc_path")" > "$sha_path"

BACKUP_MANIFEST_PATH="$manifest_path" \
BACKUP_FILE_NAME="$(basename "$enc_path")" \
BACKUP_SHA256="$encrypted_sha" \
BACKUP_CREATED_UTC="$utc_stamp" \
BACKUP_GIT_SHA="$git_sha" \
BACKUP_SOURCE_KIND="$source_kind" \
python3 - <<'PY'
import json, os
from pathlib import Path
payload = {
    "version": 1,
    "created_utc": os.environ["BACKUP_CREATED_UTC"],
    "file": os.environ["BACKUP_FILE_NAME"],
    "sha256": os.environ["BACKUP_SHA256"],
    "git_sha": os.environ["BACKUP_GIT_SHA"],
    "source_kind": os.environ["BACKUP_SOURCE_KIND"],
    "encrypted": True,
    "encryption": "age",
}
Path(os.environ["BACKUP_MANIFEST_PATH"]).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY

upload_one() {
  local remote="$1"
  local label="$2"
  log "Feltöltés: $label"
  rclone copyto "$enc_path" "$remote/$(basename "$enc_path")"
  rclone copyto "$sha_path" "$remote/$(basename "$sha_path")"
  rclone copyto "$manifest_path" "$remote/$(basename "$manifest_path")"

  # Fail-closed ellenőrzés: mindhárom objektumnak ténylegesen láthatónak kell lennie.
  rclone lsjson "$remote/$(basename "$enc_path")" --stat >/dev/null
  rclone lsjson "$remote/$(basename "$sha_path")" --stat >/dev/null
  rclone lsjson "$remote/$(basename "$manifest_path")" --stat >/dev/null
}

upload_one "$GDRIVE_REMOTE" "Google Drive"
upload_one "$B2_REMOTE" "Backblaze B2"

log "SUCCESS: mindkét külső cél ellenőrzötten megkapta a mentést"
printf 'BACKUP_FILE=%s\nBACKUP_SHA256=%s\nBACKUP_MANIFEST=%s\n' \
  "$(basename "$enc_path")" "$encrypted_sha" "$manifest_path"
