#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
cleanup() { rm -rf "$test_root"; }
trap cleanup EXIT

fake_bin="$test_root/bin"
remote_root="$test_root/remotes"
mkdir -p "$fake_bin" "$remote_root/gdrive/backups" "$remote_root/b2/backups"

cat > "$fake_bin/rclone" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cmd="${1:-}"
shift || true
remote_to_path() {
  local remote="$1"
  local provider="${remote%%:*}"
  local path="${remote#*:}"
  printf '%s/%s/%s' "$FAKE_RCLONE_ROOT" "$provider" "$path"
}
case "$cmd" in
  lsf)
    target="$(remote_to_path "$1")"
    find "$target" -maxdepth 1 -type f -printf '%f\n' | sort
    ;;
  deletefile)
    target="$(remote_to_path "$1")"
    rm "$target"
    ;;
  *)
    echo "Unexpected rclone command: $cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_bin/rclone"

export PATH="$fake_bin:$PATH"
export FAKE_RCLONE_ROOT="$remote_root"
export BACKUP_GDRIVE_REMOTE="gdrive:backups"
export BACKUP_B2_REMOTE="b2:backups"
export RETENTION_NOW_UTC="2026-08-31T12:00:00Z"

make_pair() {
  local provider="$1"
  local timestamp="$2"
  local sha="abcdef123456"
  local name="ahely-booking-production_${timestamp}_${sha}.tar.gz.age"
  printf 'encrypted\n' > "$remote_root/$provider/backups/$name"
  printf 'checksum\n' > "$remote_root/$provider/backups/$name.sha256"
}

seed_provider() {
  local provider="$1"
  # <15 days: all four must stay.
  for t in 20260830T060000Z 20260830T100000Z 20260830T140000Z 20260830T180000Z; do make_pair "$provider" "$t"; done
  # 20 days old: GDrive keeps one; B2 keeps all because of 30-day Object Lock window.
  for t in 20260811T060000Z 20260811T100000Z 20260811T140000Z 20260811T180000Z; do make_pair "$provider" "$t"; done
  # 40 days old: both keep only the latest local-day backup.
  for t in 20260722T060000Z 20260722T100000Z 20260722T140000Z 20260722T180000Z; do make_pair "$provider" "$t"; done
  # Older than 90 days but inside 24 months: one latest backup per local month.
  for t in 20260501T060000Z 20260515T100000Z 20260531T180000Z; do make_pair "$provider" "$t"; done
  # Older than 24 calendar months: no automatic retention.
  for t in 20240501T060000Z 20240531T180000Z; do make_pair "$provider" "$t"; done
}

seed_provider gdrive
seed_provider b2

before_gdrive="$(find "$remote_root/gdrive/backups" -type f | wc -l)"
before_b2="$(find "$remote_root/b2/backups" -type f | wc -l)"

dry_output="$test_root/dry-run.log"
python3 "$repo_root/scripts/retention-production.py" > "$dry_output"

if [ "$(find "$remote_root/gdrive/backups" -type f | wc -l)" -ne "$before_gdrive" ] || [ "$(find "$remote_root/b2/backups" -type f | wc -l)" -ne "$before_b2" ]; then
  echo "Dry-run modified remote files" >&2
  exit 1
fi

if ! grep -q 'WOULD_DELETE Google Drive' "$dry_output" || ! grep -q 'WOULD_DELETE Backblaze B2' "$dry_output"; then
  echo "Dry-run did not report planned deletions" >&2
  exit 1
fi

python3 "$repo_root/scripts/retention-production.py" --apply > "$test_root/apply.log"

artifact_count() { find "$remote_root/$1/backups" -type f -name '*.tar.gz.age' | wc -l; }

# Expected GDrive artifacts: 4 recent + 1 from 20d + 1 from 40d + 1 monthly = 7.
if [ "$(artifact_count gdrive)" -ne 7 ]; then
  echo "Unexpected Google Drive artifact count after retention" >&2
  find "$remote_root/gdrive/backups" -type f -printf '%f\n' | sort >&2
  exit 1
fi

# Expected B2 artifacts: 4 recent + all 4 from 20d lock window + 1 from 40d + 1 monthly = 10.
if [ "$(artifact_count b2)" -ne 10 ]; then
  echo "Unexpected B2 artifact count after retention" >&2
  find "$remote_root/b2/backups" -type f -printf '%f\n' | sort >&2
  exit 1
fi

# Latest daily/monthly restore points must survive.
for provider in gdrive b2; do
  for timestamp in 20260722T180000Z 20260531T180000Z; do
    name="ahely-booking-production_${timestamp}_abcdef123456.tar.gz.age"
    test -f "$remote_root/$provider/backups/$name"
    test -f "$remote_root/$provider/backups/$name.sha256"
  done
  if find "$remote_root/$provider/backups" -type f -name 'ahely-booking-production_202405*.tar.gz.age' -print -quit | grep -q .; then
    echo "Backup older than 24 months was unexpectedly retained on $provider" >&2
    exit 1
  fi
done

# Missing sidecar must fail closed without deleting the recognized artifact.
broken="ahely-booking-production_20260701T180000Z_abcdef123456.tar.gz.age"
printf 'encrypted\n' > "$remote_root/gdrive/backups/$broken"
printf 'encrypted\n' > "$remote_root/b2/backups/$broken"
if python3 "$repo_root/scripts/retention-production.py" --apply > "$test_root/broken.log" 2>&1; then
  echo "Retention unexpectedly succeeded with missing checksum sidecars" >&2
  exit 1
fi
test -f "$remote_root/gdrive/backups/$broken"
test -f "$remote_root/b2/backups/$broken"

printf '%s\n' "Production retention policy tests passed."
