#!/usr/bin/env bash
set -euo pipefail

: "${BACKUP_B2_ACCOUNT_ID:?Missing BACKUP_B2_ACCOUNT_ID (Backblaze application key ID)}"
: "${BACKUP_B2_APPLICATION_KEY:?Missing BACKUP_B2_APPLICATION_KEY}"
: "${BACKUP_B2_REMOTE:?Missing BACKUP_B2_REMOTE}"
: "${B2_OBJECT_LOCK_CONFIRMATION:?Missing B2_OBJECT_LOCK_CONFIRMATION}"

if [[ "$B2_OBJECT_LOCK_CONFIRMATION" != "GOVERNANCE_30" ]]; then
  echo "Refusing to change B2 Object Lock: confirmation must be GOVERNANCE_30" >&2
  exit 2
fi

bucket_name="${BACKUP_B2_REMOTE#b2:}"
if [[ -z "$bucket_name" || "$bucket_name" == "$BACKUP_B2_REMOTE" || "$bucket_name" == */* ]]; then
  echo "BACKUP_B2_REMOTE must have exact form b2:<bucket-name>" >&2
  exit 2
fi

for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 2; }
done

auth_json="$(curl --fail-with-body --silent --show-error \
  --user "${BACKUP_B2_ACCOUNT_ID}:${BACKUP_B2_APPLICATION_KEY}" \
  https://api.backblazeb2.com/b2api/v4/b2_authorize_account)"

api_url="$(jq -r '.apiInfo.storageApi.apiUrl // empty' <<<"$auth_json")"
auth_token="$(jq -r '.authorizationToken // empty' <<<"$auth_json")"
account_id="$(jq -r '.accountId // empty' <<<"$auth_json")"

if [[ -z "$api_url" || -z "$auth_token" || -z "$account_id" ]]; then
  echo "Backblaze authorization response is incomplete" >&2
  exit 2
fi

for capability in readBucketRetentions writeBucketRetentions listBuckets; do
  if ! jq -e --arg cap "$capability" '.apiInfo.storageApi.allowed.capabilities | index($cap) != null' <<<"$auth_json" >/dev/null; then
    echo "Backblaze application key is missing required capability: $capability" >&2
    exit 2
  fi
done

bucket_id="$(jq -r --arg name "$bucket_name" \
  '.apiInfo.storageApi.allowed.buckets[]? | select(.name == $name) | .id' <<<"$auth_json" | head -n1)"

if [[ -z "$bucket_id" ]]; then
  echo "Authorized key is not restricted to / does not expose expected bucket: $bucket_name" >&2
  exit 2
fi

list_payload="$(jq -nc --arg accountId "$account_id" --arg bucketId "$bucket_id" \
  '{accountId:$accountId,bucketId:$bucketId}')"

before_json="$(curl --fail-with-body --silent --show-error \
  -H "Authorization: $auth_token" \
  -H 'Content-Type: application/json' \
  -d "$list_payload" \
  "$api_url/b2api/v4/b2_list_buckets")"

if ! jq -e --arg id "$bucket_id" \
  '.buckets[] | select(.bucketId == $id) | .fileLockConfiguration.value.isFileLockEnabled == true' \
  <<<"$before_json" >/dev/null; then
  echo "Expected bucket does not report Object Lock enabled; refusing to continue" >&2
  exit 2
fi

current_mode="$(jq -r --arg id "$bucket_id" \
  '.buckets[] | select(.bucketId == $id) | .fileLockConfiguration.value.defaultRetention.mode // ""' \
  <<<"$before_json")"
current_duration="$(jq -r --arg id "$bucket_id" \
  '.buckets[] | select(.bucketId == $id) | .fileLockConfiguration.value.defaultRetention.period.duration // ""' \
  <<<"$before_json")"
current_unit="$(jq -r --arg id "$bucket_id" \
  '.buckets[] | select(.bucketId == $id) | .fileLockConfiguration.value.defaultRetention.period.unit // ""' \
  <<<"$before_json")"

if [[ "$current_mode" == "governance" && "$current_duration" == "30" && "$current_unit" == "days" ]]; then
  echo "B2 Object Lock already configured: governance / 30 days"
  exit 0
fi

if [[ -n "$current_mode" && "$current_mode" != "governance" ]]; then
  echo "Existing default retention mode is '$current_mode', not governance; refusing to overwrite automatically" >&2
  exit 2
fi

update_payload="$(jq -nc \
  --arg accountId "$account_id" \
  --arg bucketId "$bucket_id" \
  '{accountId:$accountId,bucketId:$bucketId,defaultRetention:{mode:"governance",period:{duration:30,unit:"days"}}}')"

update_json="$(curl --fail-with-body --silent --show-error \
  -H "Authorization: $auth_token" \
  -H 'Content-Type: application/json' \
  -d "$update_payload" \
  "$api_url/b2api/v4/b2_update_bucket")"

if ! jq -e \
  '.fileLockConfiguration.value.isFileLockEnabled == true and
   .fileLockConfiguration.value.defaultRetention.mode == "governance" and
   .fileLockConfiguration.value.defaultRetention.period.duration == 30 and
   .fileLockConfiguration.value.defaultRetention.period.unit == "days"' \
  <<<"$update_json" >/dev/null; then
  echo "Backblaze update response did not confirm governance / 30 days" >&2
  exit 2
fi

verify_json="$(curl --fail-with-body --silent --show-error \
  -H "Authorization: $auth_token" \
  -H 'Content-Type: application/json' \
  -d "$list_payload" \
  "$api_url/b2api/v4/b2_list_buckets")"

if ! jq -e --arg id "$bucket_id" \
  '.buckets[] | select(.bucketId == $id) |
   .fileLockConfiguration.value.isFileLockEnabled == true and
   .fileLockConfiguration.value.defaultRetention.mode == "governance" and
   .fileLockConfiguration.value.defaultRetention.period.duration == 30 and
   .fileLockConfiguration.value.defaultRetention.period.unit == "days"' \
  <<<"$verify_json" >/dev/null; then
  echo "Post-update verification failed: governance / 30 days not observed" >&2
  exit 2
fi

echo "PASS: B2 bucket '$bucket_name' default Object Lock retention is governance / 30 days"
