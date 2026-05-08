#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
ENV_FILE_PATH="${2:-}"
shift 2 || true

if [[ -z "$ACTION" || -z "$ENV_FILE_PATH" ]]; then
  echo "Usage: pdc-action-dispatch.sh <action> <env-file-path> [--payload-json <json>] [--param key=value] [--dry-run]" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE_PATH" ]]; then
  echo "Environment file not found: $ENV_FILE_PATH" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PAYLOAD_JSON=""
DRY_RUN="false"
declare -A PARAMS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload-json)
      PAYLOAD_JSON="${2:-}"
      shift 2
      ;;
    --param)
      kv="${2:-}"
      if [[ "$kv" == *"="* ]]; then
        key="${kv%%=*}"
        value="${kv#*=}"
        PARAMS["$key"]="$value"
      fi
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    *)
      echo "Ignoring unknown argument: $1" >&2
      shift
      ;;
  esac
done

# shellcheck disable=SC1090
source "$ENV_FILE_PATH"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 2
  fi
}

require_tool curl
require_tool jq

resolve_base_url() {
  local raw="${PDC_API_BASE_URL:-${PDC_SERVER_URL:-${PDC_URL:-${PENTAHO_HOST:-}}}}"
  if [[ -z "$raw" ]]; then
    echo ""
    return
  fi
  if [[ "$raw" != http*://* ]]; then
    raw="https://$raw"
  fi
  raw="${raw%/}"
  printf '%s/api/public/v1' "$raw"
}

BASE_URL="$(resolve_base_url)"
if [[ -z "$BASE_URL" ]]; then
  echo "Could not resolve PDC base URL. Set PDC_API_BASE_URL or PDC_SERVER_URL in env file." >&2
  exit 2
fi

PDC_USER="${PDC_API_USERNAME:-${PDC_USERNAME:-}}"
PDC_PASS="${PDC_API_PASSWORD:-${PDC_PASSWORD:-}}"
if [[ -z "$PDC_USER" || -z "$PDC_PASS" ]]; then
  echo "Missing API credentials. Set PDC_API_USERNAME/PDC_API_PASSWORD or PDC_USERNAME/PDC_PASSWORD." >&2
  exit 2
fi

auth() {
  local response
  response="$(curl -sSk -X POST "$BASE_URL/auth" \
    -H 'accept: application/json' \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "username=$PDC_USER" \
    --data-urlencode "password=$PDC_PASS" \
    --data-urlencode 'client_id=pdc-client' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode 'scope=openid profile email')"
  echo "$response" | jq -e '.data.accessToken' >/dev/null
  echo "$response" | jq -r '.data.accessToken'
}

TOKEN="$(auth)"

api_call() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="$BASE_URL$path"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN $method $url"
    if [[ -n "$payload" ]]; then
      echo "$payload" | jq . || echo "$payload"
    fi
    return 0
  fi

  if [[ -n "$payload" ]]; then
    curl -sSk -X "$method" "$url" \
      -H 'accept: application/json' \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$payload"
  else
    curl -sSk -X "$method" "$url" \
      -H 'accept: application/json' \
      -H "Authorization: Bearer $TOKEN"
  fi
}

payload_or_default() {
  local default="$1"
  if [[ -n "$PAYLOAD_JSON" ]]; then
    echo "$PAYLOAD_JSON"
  else
    echo "$default"
  fi
}

run_preflight() {
  log "Preflight: validating token and notifications endpoint"
  api_call GET "/notifications" "" | jq .
}

run_datasource() {
  local payload
  local default_name
  default_name="automation-ds-$(date +%s)"
  payload="$(payload_or_default "{\"resourceName\":\"$default_name\",\"databaseType\":\"postgresql\"}")"
  log "Data source action"
  api_call POST "/data-sources" "$payload" | jq .
}

list_datasources() {
  log "Listing all data sources (shows _id, resourceName, databaseType, pId)"
  api_call GET "/data-sources" "" | jq '[.[] | {_id, resourceName, databaseType, pId}]'
}

run_ingest() {
  local payload
  payload="$(payload_or_default '{}')"
  log "Ingest action"
  api_call POST "/jobs/execute/metadata/ingest" "$payload" | jq .
}

run_collection() {
  local payload
  payload="$(payload_or_default '{"name":"automation-collection","type":"dataset"}')"
  log "Collection action"
  api_call POST "/data-collections" "$payload" | jq .
}

run_profile() {
  local payload
  payload="$(payload_or_default '{}')"
  log "Profile action"
  api_call POST "/jobs/execute/collections/data-profiling" "$payload" | jq .
}

run_aggregate() {
  local payload
  payload="$(payload_or_default '{}')"
  log "Aggregate action"
  api_call POST "/jobs/execute/collections/data-aggregation" "$payload" | jq .
}

run_results() {
  local payload
  payload="$(payload_or_default '{}')"
  log "Results action"
  api_call POST "/data-collections/by-ids/profiling-info" "$payload" | jq .
}

run_tagging() {
  local entity_id="${PARAMS[entity-id]:-${PARAMS[entity_id]:-}}"
  local payload="$PAYLOAD_JSON"

  if [[ -z "$entity_id" ]]; then
    echo "Tagging requires --param entity-id=<uuid> (or entity_id)." >&2
    exit 2
  fi

  if [[ -z "$payload" ]]; then
    local tags_csv="${PARAMS[tags]:-managed}"
    payload="$(jq -nc --arg tags "$tags_csv" '{attributes: {tags: ($tags | split(",") | map({name: .}))}}')"
  fi

  log "Tagging action for entity: $entity_id"
  api_call PATCH "/entities/$entity_id" "$payload" | jq .
}

run_optional() {
  local job_type="${PARAMS[job-type]:-${PARAMS[job_type]:-discovery}}"
  local endpoint=""
  case "$job_type" in
    discovery)
      endpoint="/jobs/execute/data-discovery"
      ;;
    identification)
      endpoint="/jobs/execute/data-identification"
      ;;
    pii)
      endpoint="/jobs/execute/pii-detection"
      ;;
    trust-score)
      endpoint="/jobs/execute/calculate-trust-score"
      ;;
    *)
      echo "Unsupported optional job type: $job_type" >&2
      exit 2
      ;;
  esac

  local payload
  payload="$(payload_or_default '{}')"
  log "Optional action: $job_type"
  api_call POST "$endpoint" "$payload" | jq .
}

run_all() {
  log "Run-all action"
  run_preflight
  log "Run-all currently executes preflight baseline and expects explicit step payloads for subsequent actions."
}

case "$ACTION" in
  preflight) run_preflight ;;
  datasource) run_datasource ;;
  list-datasources) list_datasources ;;
  ingest) run_ingest ;;
  collection) run_collection ;;
  profile) run_profile ;;
  aggregate) run_aggregate ;;
  results) run_results ;;
  tagging) run_tagging ;;
  optional) run_optional ;;
  run-all) run_all ;;
  *)
    echo "Unsupported action: $ACTION" >&2
    exit 2
    ;;
esac
