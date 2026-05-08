#!/bin/bash

# 40-migrate-pdc.sh
# Recurring PDC migration from a populated source host to a clean/target host.
# Migrates /opt/pentaho/pdc-docker-deployment/conf and all Docker volumes named pdc*.

set -euo pipefail

usage() {
    cat << 'USAGE'
Usage:
        ./40-migrate-pdc.sh <source-env-file> [target-env-file] --source-ip <ip> --target-ip <ip> [--source-user <user>] [--target-user <user>] [--stop-source] [--dry-run]

Examples:
    ./40-migrate-pdc.sh pdc-source.env pdc-target.env --source-ip 10.80.230.246 --target-ip 10.80.230.163
    ./40-migrate-pdc.sh pdc-10.2.10.env --source-ip 10.80.230.246 --target-ip 10.80.230.177 --source-user ec2-user
    ./40-migrate-pdc.sh pdc-10.2.10.env pdc-10.2.10-target.env --source-ip 10.80.230.246 --target-ip 10.80.230.163 --dry-run

Behavior:
  - Default mode captures source conf and volumes LIVE without stopping or restarting source PDC.
    Source users remain logged in and unaffected throughout the migration.
    - If target-env-file is omitted, source-env-file is used for both source and target defaults.
  - --stop-source is an advanced option that briefly stops source PDC before capture for perfect
    volume consistency, then restarts it. Use only during a scheduled maintenance window.
    - --dry-run validates connectivity and prerequisites only; no stop/copy/restore changes are made.

Optional env vars (in source/target env files):
  PDC_MIGRATION_SOURCE_SSH_USER
  PDC_MIGRATION_TARGET_SSH_USER
  PDC_MIGRATION_SOURCE_KEY_PATH
  PDC_MIGRATION_TARGET_KEY_PATH
  PDC_MIGRATION_WORK_DIR
USAGE
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

SOURCE_ENV_FILE_NAME="$(basename "$1")"
shift

TARGET_ENV_FILE_NAME="${SOURCE_ENV_FILE_NAME}"
if [ $# -gt 0 ] && [[ "${1}" != --* ]]; then
    TARGET_ENV_FILE_NAME="$(basename "$1")"
    shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ENV_FILE_PATH="${SCRIPT_DIR}/${SOURCE_ENV_FILE_NAME}"
TARGET_ENV_FILE_PATH="${SCRIPT_DIR}/${TARGET_ENV_FILE_NAME}"

if [ ! -f "${SOURCE_ENV_FILE_PATH}" ]; then
    echo "❌ Error: Source configuration file not found: ${SOURCE_ENV_FILE_NAME}"
    exit 1
fi

if [ ! -f "${TARGET_ENV_FILE_PATH}" ]; then
    echo "❌ Error: Target configuration file not found: ${TARGET_ENV_FILE_NAME}"
    exit 1
fi

source "${SOURCE_ENV_FILE_PATH}"
source "${SCRIPT_DIR}/_shared-helpers.sh"

read_env_value() {
    local env_file="$1"
    local var_name="$2"
    bash -c 'source "$1" >/dev/null 2>&1; eval "printf %s \"\${'"${var_name}"':-}\""' _ "${env_file}" 2>/dev/null || true
}

build_default_key_path() {
    local key_path="$1"
    local key_name="$2"

    if [ -n "${key_path}" ]; then
        echo "${key_path}"
    elif [ -n "${key_name}" ]; then
        echo "$HOME/.ssh/${key_name}.pem"
    else
        echo "$HOME/.ssh/id_rsa"
    fi
}

SOURCE_SSH_USER_DEFAULT="$(read_env_value "${SOURCE_ENV_FILE_PATH}" "PDC_MIGRATION_SOURCE_SSH_USER")"
[ -z "${SOURCE_SSH_USER_DEFAULT}" ] && SOURCE_SSH_USER_DEFAULT="$(read_env_value "${SOURCE_ENV_FILE_PATH}" "SSH_USER")"

TARGET_SSH_USER_DEFAULT="$(read_env_value "${TARGET_ENV_FILE_PATH}" "PDC_MIGRATION_TARGET_SSH_USER")"
[ -z "${TARGET_SSH_USER_DEFAULT}" ] && TARGET_SSH_USER_DEFAULT="$(read_env_value "${TARGET_ENV_FILE_PATH}" "SSH_USER")"

SOURCE_KEY_PATH_DEFAULT="$(read_env_value "${SOURCE_ENV_FILE_PATH}" "PDC_MIGRATION_SOURCE_KEY_PATH")"
if [ -z "${SOURCE_KEY_PATH_DEFAULT}" ]; then
    SOURCE_KEY_PATH_DEFAULT="$(build_default_key_path "$(read_env_value "${SOURCE_ENV_FILE_PATH}" "KEY_PATH")" "$(read_env_value "${SOURCE_ENV_FILE_PATH}" "KEY_NAME")")"
fi

TARGET_KEY_PATH_DEFAULT="$(read_env_value "${TARGET_ENV_FILE_PATH}" "PDC_MIGRATION_TARGET_KEY_PATH")"
if [ -z "${TARGET_KEY_PATH_DEFAULT}" ]; then
    TARGET_KEY_PATH_DEFAULT="$(build_default_key_path "$(read_env_value "${TARGET_ENV_FILE_PATH}" "KEY_PATH")" "$(read_env_value "${TARGET_ENV_FILE_PATH}" "KEY_NAME")")"
fi

SOURCE_IP=""
TARGET_IP=""
STOP_SOURCE="false"
DRY_RUN="false"
SOURCE_SSH_USER="${SOURCE_SSH_USER_DEFAULT:-ubuntu}"
TARGET_SSH_USER="${TARGET_SSH_USER_DEFAULT:-ubuntu}"

while [ $# -gt 0 ]; do
    case "$1" in
        --source-ip)
            [ $# -lt 2 ] && { echo "❌ Missing value for --source-ip"; exit 1; }
            SOURCE_IP="$2"
            shift 2
            ;;
        --target-ip)
            [ $# -lt 2 ] && { echo "❌ Missing value for --target-ip"; exit 1; }
            TARGET_IP="$2"
            shift 2
            ;;
        --source-user)
            [ $# -lt 2 ] && { echo "❌ Missing value for --source-user"; exit 1; }
            SOURCE_SSH_USER="$2"
            shift 2
            ;;
        --target-user)
            [ $# -lt 2 ] && { echo "❌ Missing value for --target-user"; exit 1; }
            TARGET_SSH_USER="$2"
            shift 2
            ;;
        --stop-source)
            STOP_SOURCE="true"
            shift
            ;;
        --live-copy)
            # Deprecated alias kept for backward compatibility — live-copy is now the default.
            # --stop-source is the new opt-in flag to stop source for consistency.
            echo "ℹ️  --live-copy is deprecated (live capture is now the default). Ignoring."
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "${SOURCE_IP}" ] || [ -z "${TARGET_IP}" ]; then
    echo "❌ Error: source and target IPs are required"
    echo "   Pass --source-ip and --target-ip"
    exit 1
fi

if [ "${SOURCE_IP}" = "${TARGET_IP}" ]; then
    echo "❌ Error: source and target IP cannot be the same"
    exit 1
fi

SOURCE_KEY_PATH="${PDC_MIGRATION_SOURCE_KEY_PATH:-${SOURCE_KEY_PATH_DEFAULT}}"
TARGET_KEY_PATH="${PDC_MIGRATION_TARGET_KEY_PATH:-${TARGET_KEY_PATH_DEFAULT}}"
SOURCE_KEY_PATH="$(resolve_key_path "${SOURCE_KEY_PATH}")"
TARGET_KEY_PATH="$(resolve_key_path "${TARGET_KEY_PATH}")"

if [ ! -f "${SOURCE_KEY_PATH}" ]; then
    echo "❌ Source key file not found: ${SOURCE_KEY_PATH}"
    exit 1
fi
if [ ! -f "${TARGET_KEY_PATH}" ]; then
    echo "❌ Target key file not found: ${TARGET_KEY_PATH}"
    exit 1
fi

MIGRATION_ID="$(date +%Y%m%d-%H%M%S)"
LOCAL_WORK_DIR="${PDC_MIGRATION_WORK_DIR:-${SCRIPT_DIR}/generatedFiles/pdc-migration-${MIGRATION_ID}}"
LOCAL_BUNDLE_PATH="${LOCAL_WORK_DIR}/pdc-migration-${MIGRATION_ID}.tgz"
REMOTE_SOURCE_BUNDLE="/tmp/pdc-migration-${MIGRATION_ID}.tgz"
REMOTE_TARGET_BUNDLE="/tmp/pdc-migration-${MIGRATION_ID}.tgz"

echo "🚚 PDC Migration"
echo "================"
echo "📋 Source Env File: ${SOURCE_ENV_FILE_NAME}"
echo "📋 Target Env File: ${TARGET_ENV_FILE_NAME}"
echo "📋 Source Host: ${SOURCE_IP}"
echo "📋 Source User: ${SOURCE_SSH_USER}"
echo "📋 Target Host: ${TARGET_IP}"
echo "📋 Target User: ${TARGET_SSH_USER}"
echo "📋 Source Mode: $( [ "${STOP_SOURCE}" = "true" ] && echo "STOP SOURCE (brief outage, maximum consistency)" || echo "LIVE CAPTURE (non-disruptive, recommended)" )"
echo "📋 Dry Run: $( [ "${DRY_RUN}" = "true" ] && echo "YES (no changes will be made)" || echo "NO" )"
echo "📋 Migration ID: ${MIGRATION_ID}"
echo ""

mkdir -p "${LOCAL_WORK_DIR}"

cleanup_local() {
    rm -f "${LOCAL_BUNDLE_PATH}" 2>/dev/null || true
}
trap cleanup_local EXIT

ssh_source() {
    ssh -i "${SOURCE_KEY_PATH}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SOURCE_SSH_USER}@${SOURCE_IP}" "$@"
}

ssh_target() {
    ssh -i "${TARGET_KEY_PATH}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${TARGET_SSH_USER}@${TARGET_IP}" "$@"
}

echo "🔍 Step 1/5: Validating SSH and PDC prerequisites"

echo "   - Source connectivity"
ssh_source "echo connected >/dev/null"

echo "   - Target connectivity"
ssh_target "echo connected >/dev/null"

ssh_source "test -x /opt/pentaho/pdc-docker-deployment/pdc.sh"
ssh_target "test -x /opt/pentaho/pdc-docker-deployment/pdc.sh"

SOURCE_VOLUME_COUNT="$(ssh_source "sudo docker volume ls --format '{{.Name}}' | grep '^pdc' | wc -l | tr -d ' '")"
TARGET_VOLUME_COUNT="$(ssh_target "sudo docker volume ls --format '{{.Name}}' | grep '^pdc' | wc -l | tr -d ' '")"

echo "   - Source pdc* volumes: ${SOURCE_VOLUME_COUNT}"
echo "   - Target pdc* volumes: ${TARGET_VOLUME_COUNT}"

if [ "${SOURCE_VOLUME_COUNT}" = "0" ]; then
    echo "❌ Source has no pdc* volumes to migrate"
    exit 1
fi

echo "✅ Prerequisites validated"
echo ""

if [ "${DRY_RUN}" = "true" ]; then
    echo "🧪 Dry run summary"
    echo "=================="
    echo "Would perform these actions:"
    echo "  1. Build migration bundle on source (${SOURCE_IP}) — source stays UP throughout"
    if [ "${STOP_SOURCE}" = "true" ]; then
        echo "     ⚠️  --stop-source: source PDC will be briefly stopped then restarted"
    fi
    echo "  2. Transfer bundle source -> local -> target"
    echo "  3. Stop target PDC and backup target conf/volume list"
    echo "  4. Restore source conf and pdc* volumes onto target"
    echo "  5. Start target PDC and print container status"
    echo ""
    echo "No data was copied and no services were stopped."
    exit 0
fi

echo "📦 Step 2/5: Building migration bundle on source (${SOURCE_IP})"
ssh_source "bash -s -- '${MIGRATION_ID}' '${STOP_SOURCE}' '${SOURCE_SSH_USER}'" << 'SRC_BUNDLE'
set -euo pipefail

MIGRATION_ID="$1"
STOP_SOURCE="$2"
OWNER_USER="$3"

PDC_DIR="/opt/pentaho/pdc-docker-deployment"
WORK_DIR="/tmp/pdc-migration-${MIGRATION_ID}"
BUNDLE_PATH="/tmp/pdc-migration-${MIGRATION_ID}.tgz"
VOLUME_LIST_FILE="${WORK_DIR}/volume-list.txt"
SOURCE_WAS_STOPPED="false"

restore_source_if_stopped() {
    if [ "${SOURCE_WAS_STOPPED}" = "true" ]; then
        echo "▶️  Restarting source PDC services (stopped by --stop-source)..."
        sudo bash "${PDC_DIR}/pdc.sh" up >/dev/null 2>&1 || true
        echo "✅ Source services restart command sent"
    fi
}
trap restore_source_if_stopped EXIT

sudo rm -rf "${WORK_DIR}" "${BUNDLE_PATH}"
mkdir -p "${WORK_DIR}/conf" "${WORK_DIR}/volumes"

if [ "${STOP_SOURCE}" = "true" ]; then
    echo "⏹️  Stopping source PDC services for consistent capture (--stop-source)..."
    sudo bash "${PDC_DIR}/pdc.sh" stop >/dev/null 2>&1 || true
    SOURCE_WAS_STOPPED="true"
else
    echo "📸 Live capture: source PDC services remain up and users are unaffected"
fi

echo "📁 Capturing conf/.env and runtime config..."
sudo tar -C "${PDC_DIR}/conf" -cf - . | tar -C "${WORK_DIR}/conf" -xf -

echo "📚 Discovering PDC volumes (pdc*)..."
mapfile -t VOLUMES < <(sudo docker volume ls --format '{{.Name}}' | grep '^pdc' || true)
if [ ${#VOLUMES[@]} -eq 0 ]; then
    echo "❌ No docker volumes matching pdc* found on source"
    exit 1
fi
printf "%s\n" "${VOLUMES[@]}" > "${VOLUME_LIST_FILE}"

echo "💾 Capturing volume data..."
for vol in "${VOLUMES[@]}"; do
    echo "   - ${vol}"
    mkdir -p "${WORK_DIR}/volumes/${vol}"
    sudo docker run --rm \
      -v "${vol}:/from:ro" \
      -v "${WORK_DIR}/volumes/${vol}:/to" \
      alpine:3.20 sh -c 'cd /from && tar -cf - . | tar -xf - -C /to'
done

echo "🧾 Writing bundle metadata..."
cat > "${WORK_DIR}/manifest.txt" << MANIFEST
migration_id=${MIGRATION_ID}
created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname=$(hostname)
stop_source=${STOP_SOURCE}
volume_count=${#VOLUMES[@]}
MANIFEST

sudo tar -C "${WORK_DIR}" -czf "${BUNDLE_PATH}" .
sudo chown "${OWNER_USER}:${OWNER_USER}" "${BUNDLE_PATH}" || true

echo "✅ Source bundle ready: ${BUNDLE_PATH}"
ls -lh "${BUNDLE_PATH}"

sudo rm -rf "${WORK_DIR}"
SRC_BUNDLE

echo "✅ Source bundle created"
echo ""

echo "🚛 Step 3/5: Transferring bundle source -> local -> target"
rsync -avP --partial -e "ssh -i ${SOURCE_KEY_PATH} -o StrictHostKeyChecking=no" \
    "${SOURCE_SSH_USER}@${SOURCE_IP}:${REMOTE_SOURCE_BUNDLE}" "${LOCAL_BUNDLE_PATH}"
rsync -avP --partial -e "ssh -i ${TARGET_KEY_PATH} -o StrictHostKeyChecking=no" \
    "${LOCAL_BUNDLE_PATH}" "${TARGET_SSH_USER}@${TARGET_IP}:${REMOTE_TARGET_BUNDLE}"

echo "✅ Bundle transferred"
echo ""

echo "♻️  Step 4/5: Restoring bundle on target (${TARGET_IP})"
ssh_target "bash -s -- '${MIGRATION_ID}' '${REMOTE_TARGET_BUNDLE}' '${TARGET_SSH_USER}' '${TARGET_IP}'" << 'TARGET_RESTORE'
set -euo pipefail

MIGRATION_ID="$1"
BUNDLE_PATH="$2"
OWNER_USER="$3"
TARGET_IP="$4"

PDC_DIR="/opt/pentaho/pdc-docker-deployment"
RESTORE_DIR="/tmp/pdc-restore-${MIGRATION_ID}"
BACKUP_ROOT="/opt/pdc-migration-backups/${MIGRATION_ID}"

if [ ! -f "${BUNDLE_PATH}" ]; then
    echo "❌ Bundle not found on target: ${BUNDLE_PATH}"
    exit 1
fi

sudo mkdir -p "${BACKUP_ROOT}"

echo "⏹️  Stopping target PDC services..."
sudo bash "${PDC_DIR}/pdc.sh" stop >/dev/null 2>&1 || true

echo "🛟 Backing up current target conf and volume list..."
sudo mkdir -p "${BACKUP_ROOT}/target-conf"
if [ -d "${PDC_DIR}/conf" ]; then
    sudo tar -C "${PDC_DIR}/conf" -cf - . | sudo tar -C "${BACKUP_ROOT}/target-conf" -xf -
fi
sudo docker volume ls --format '{{.Name}}' | grep '^pdc' | sudo tee "${BACKUP_ROOT}/target-volumes-before.txt" >/dev/null || true

echo "📦 Extracting migration bundle..."
sudo rm -rf "${RESTORE_DIR}"
sudo mkdir -p "${RESTORE_DIR}"
sudo tar -xzf "${BUNDLE_PATH}" -C "${RESTORE_DIR}"

if ! sudo test -f "${RESTORE_DIR}/manifest.txt"; then
    echo "❌ Invalid bundle: manifest.txt missing"
    exit 1
fi

echo "📁 Restoring conf..."
sudo mkdir -p "${PDC_DIR}/conf"
sudo find "${PDC_DIR}/conf" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo tar -C "${RESTORE_DIR}/conf" -cf - . | sudo tar -C "${PDC_DIR}/conf" -xf -

if [ ! -f "${PDC_DIR}/conf/.env" ]; then
    echo "❌ Restored conf/.env is missing"
    exit 1
fi

echo "🛠️  Aligning restored conf/.env to target host..."
if sudo grep -q '^GLOBAL_SERVER_HOST_NAME=' "${PDC_DIR}/conf/.env"; then
    sudo sed -i "s|^GLOBAL_SERVER_HOST_NAME=.*|GLOBAL_SERVER_HOST_NAME=${TARGET_IP}|" "${PDC_DIR}/conf/.env"
else
    echo "GLOBAL_SERVER_HOST_NAME=${TARGET_IP}" | sudo tee -a "${PDC_DIR}/conf/.env" >/dev/null
fi

echo "🛠️  Validating licensing variables for migrated target..."
licensing_server_url="$(sudo grep -E '^LICENSING_SERVER_URL=' "${PDC_DIR}/conf/.env" | tail -1 | cut -d= -f2-)"
pdi_license_url="$(sudo grep -E '^PDI_LICENSE_URL=' "${PDC_DIR}/conf/.env" | tail -1 | cut -d= -f2-)"
if [ -n "${licensing_server_url}" ] && [ -z "${pdi_license_url}" ]; then
    echo "PDI_LICENSE_URL=${licensing_server_url}" | sudo tee -a "${PDC_DIR}/conf/.env" >/dev/null
    echo "   ✅ Added PDI_LICENSE_URL from LICENSING_SERVER_URL"
fi

ensure_uuid_env_var() {
    local key="$1"
    local uuid_val=""
    if sudo grep -q "^${key}=" "${PDC_DIR}/conf/.env"; then
        return
    fi

    if command -v uuidgen >/dev/null 2>&1; then
        uuid_val="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    else
        uuid_val="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
    fi

    if [ -z "${uuid_val}" ]; then
        uuid_val="$(openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')"
    fi

    echo "${key}=\"${uuid_val}\"" | sudo tee -a "${PDC_DIR}/conf/.env" >/dev/null
}

ensure_uuid_env_var "PDC_WS_REMOTE_JOB_SERVER_ID"
ensure_uuid_env_var "PDC_WS_DEFAULT_JOB_SERVER_ID"

echo "🛠️  Removing restored TLS artifacts so they are regenerated for target host..."
sudo rm -f "${PDC_DIR}/conf/https/server.crt" "${PDC_DIR}/conf/https/server.key" "${PDC_DIR}/conf/extra-certs/bundle.pem"

echo "💾 Restoring PDC volumes..."
if ! sudo test -f "${RESTORE_DIR}/volume-list.txt"; then
    echo "❌ Invalid bundle: volume-list.txt missing"
    exit 1
fi

while IFS= read -r vol; do
    [ -z "${vol}" ] && continue
    echo "   - ${vol}"
    sudo docker volume create "${vol}" >/dev/null
    sudo docker run --rm -v "${vol}:/to" alpine:3.20 sh -c 'rm -rf /to/* /to/.[!.]* /to/..?* || true'
    sudo docker run --rm \
      -v "${vol}:/to" \
      -v "${RESTORE_DIR}/volumes/${vol}:/from:ro" \
      alpine:3.20 sh -c 'cd /from && tar -cf - . | tar -xf - -C /to'
done < <(sudo cat "${RESTORE_DIR}/volume-list.txt")

echo "▶️  Starting target PDC services..."
sudo bash "${PDC_DIR}/pdc.sh" up >/dev/null 2>&1 || true

echo "📋 Target container status (top 20):"
sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20 || true

sudo rm -rf "${RESTORE_DIR}"
sudo rm -f "${BUNDLE_PATH}"
chown "${OWNER_USER}:${OWNER_USER}" "${BACKUP_ROOT}" >/dev/null 2>&1 || true

echo "✅ Restore complete on target"
echo "   Backup saved at: ${BACKUP_ROOT}"
TARGET_RESTORE

echo "✅ Target restore complete"
echo ""

echo "🧪 Step 5/5: Post-migration checks"
ssh_target "sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20"

echo "🌐 Checking target root route health..."
TARGET_ROOT_STATUS="$(curl -k -s -o /dev/null -w '%{http_code}' "https://${TARGET_IP}/" || true)"

if [ "${TARGET_ROOT_STATUS}" = "302" ]; then
    echo "✅ Target root route is healthy (HTTP 302)"
elif [ "${TARGET_ROOT_STATUS}" = "404" ]; then
    echo "⚠️  Target root route returned HTTP 404. Attempting middleware recovery..."
    ssh_target "sudo docker restart pdc-um-oauth-1 pdc-fe-1 pdc-in-1 >/dev/null"
    sleep 5
    TARGET_ROOT_STATUS_RECHECK="$(curl -k -s -o /dev/null -w '%{http_code}' "https://${TARGET_IP}/" || true)"
    if [ "${TARGET_ROOT_STATUS_RECHECK}" = "302" ]; then
        echo "✅ Root route recovered (HTTP 302) after oauth/fe/ingress restart"
    else
        echo "⚠️  Root route is still returning HTTP ${TARGET_ROOT_STATUS_RECHECK:-unknown}"
        echo "   Manual follow-up: check containers pdc-um-oauth-1, pdc-fe-1, pdc-in-1 and Traefik routes"
    fi
else
    echo "⚠️  Target root route returned HTTP ${TARGET_ROOT_STATUS:-unknown}"
    echo "   Expected HTTP 302 to Keycloak/auth flow"
fi

echo ""
echo "🎉 Migration completed"
echo "======================"
echo "Migration ID: ${MIGRATION_ID}"
echo "Source: ${SOURCE_IP}"
echo "Target: ${TARGET_IP}"
echo ""
echo "Next validation (recommended):"
echo "  1. Open target PDC and verify applications/connections/glossary content"
echo "  2. Run a sample metadata scan on target"
echo "  3. Confirm user access and authentication behavior"
