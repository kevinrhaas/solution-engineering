#!/bin/bash

# Database type: set default to 'postgres', override with env or CLI arg if desired
DB_TYPE="postgres"
# Optionally allow override via environment or CLI
if [ -n "$PENTAHO_DB_TYPE" ]; then
  DB_TYPE="$PENTAHO_DB_TYPE"
fi
if [ -n "$3" ]; then
  DB_TYPE="$3"
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 <env-file> <plugin-zip-filename> [db-type]"
    echo "Example: $0 pentaho-deployment-sample.env paz-plugin-ee-11.0.0.0-136.zip"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-113.env paz-plugin-ee-11.0.0.0-136.zip mysql"
    echo ""
    echo "Database type defaults to 'postgres' (can be: postgres, mysql, sqlserver, oracle)"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
STATE_FILE_NAME="${ENV_FILE_NAME%.env}-runtime.state"
PLUGIN_ZIP_FILENAME="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"
source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

PLUGIN_DIR="${SCRIPT_DIR}/downloads/plugins/${PENTAHO_VERSION}"
PLUGIN_ZIP="${PLUGIN_DIR}/${PLUGIN_ZIP_FILENAME}"

if [ ! -f "$PLUGIN_ZIP" ]; then
    echo "❌ Plugin zip not found: $PLUGIN_ZIP"
    exit 1
fi

echo "🧭 Ensuring remote staging directory exists..."
# Try to create and use data-volume staging dir; fall back to /tmp if not available
REMOTE_STAGING_DIR=$(ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<'ENSURETMP'
set -e
if [ -d /mnt/pentaho-data ]; then
    sudo mkdir -p /mnt/pentaho-data/tmp || true
    sudo chmod 1777 /mnt/pentaho-data/tmp || true
    echo "/mnt/pentaho-data/tmp"
else
    mkdir -p /tmp || true
    echo "/tmp"
fi
ENSURETMP
)

echo "📤 Uploading plugin zip to server (staging: ${REMOTE_STAGING_DIR})..."
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$PLUGIN_ZIP" ${SSH_USER}@${SSH_IP}:"${REMOTE_STAGING_DIR}/"

echo "🔧 Installing plugin and restarting Pentaho container..."
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "export PENTAHO_VERSION='${PENTAHO_VERSION}'; export PLUGIN_ZIP_FILENAME='${PLUGIN_ZIP_FILENAME}'; export DB_TYPE='${DB_TYPE}'; export STAGING_DIR='${REMOTE_STAGING_DIR}'; bash -s" <<'ENDSSH'
set -e

# Prefer a docker tmp dir on data volume when available
if [ -d /mnt/pentaho-data ]; then
    export DOCKER_TMPDIR=/mnt/pentaho-data/docker-tmp
    sudo mkdir -p /mnt/pentaho-data/docker-tmp || true
    sudo chmod 1777 /mnt/pentaho-data/docker-tmp || true
else
    unset DOCKER_TMPDIR
fi

mkdir -p "$STAGING_DIR"
cd "$STAGING_DIR"
echo "[DEBUG] docker ps output:"
docker ps --format '{{.ID}} {{.Names}}'
echo "[DEBUG] grep/awk result:"
CONTAINER_ID=$(docker ps --format '{{.ID}} {{.Names}}' | grep pentaho-server-${DB_TYPE}-pentaho-server | awk '{print $1}')
docker ps --format '{{.ID}} {{.Names}}' | grep pentaho-server-${DB_TYPE}-pentaho-server | awk '{print $1}'
if [ -z "$CONTAINER_ID" ]; then
    echo "❌ Pentaho container $CONTAINER_ID not found!"
    exit 1
fi
echo "[DEBUG] Container status:"
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_ID")
echo "$CONTAINER_STATUS"
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "❌ Pentaho container $CONTAINER_ID is not running (status: $CONTAINER_STATUS). Aborting."
    exit 1
fi
echo "[DEBUG] $STAGING_DIR contents before docker cp:"
ls -l "$STAGING_DIR"
echo "[DEBUG] Checking /tmp in container..."
docker exec "$CONTAINER_ID" bash -c "ls -ld /tmp || mkdir -p /tmp"
echo "[DEBUG] Copying plugin zip into container from staging dir..."
docker cp "$STAGING_DIR/$PLUGIN_ZIP_FILENAME" "$CONTAINER_ID":/tmp/
echo "[DEBUG] Checking/installing unzip in container..."
docker exec -u 0 "$CONTAINER_ID" bash -c "command -v unzip >/dev/null 2>&1 || (apt-get update && apt-get install -y unzip)"
echo "[DEBUG] Listing contents of zip before extraction..."
docker exec "$CONTAINER_ID" bash -c "cd /tmp && unzip -l $PLUGIN_ZIP_FILENAME"
echo "[DEBUG] Extracting plugin zip in container..."
# Special case for app shell webclient plugin
if [[ "$PLUGIN_ZIP_FILENAME" == *pentaho-app-shell-core-webclient.zip ]]; then
    docker exec -u 0 "$CONTAINER_ID" bash -c "mkdir -p /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell && unzip -o /tmp/$PLUGIN_ZIP_FILENAME -d /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
    echo "[DEBUG] Setting ownership to pentaho:pentaho for /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell after extraction..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
    echo "[DEBUG] Listing /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell after extraction and chown..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "ls -l /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
elif [[ "$PLUGIN_ZIP_FILENAME" == *webttle* ]]; then
    docker exec -u 0 "$CONTAINER_ID" bash -c "unzip -o /tmp/$PLUGIN_ZIP_FILENAME -d /opt/pentaho/"
    echo "[DEBUG] Setting ownership to pentaho:pentaho for /opt/pentaho after extraction..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/"
    echo "[DEBUG] Listing /opt/pentaho after extraction and chown..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "ls -l /opt/pentaho/"
else
    docker exec -u 0 "$CONTAINER_ID" bash -c "unzip -o /tmp/$PLUGIN_ZIP_FILENAME -d /opt/pentaho/pentaho-server/pentaho-solutions/system"
    echo "[DEBUG] Setting ownership to pentaho:pentaho for /opt/pentaho/pentaho-server/pentaho-solutions/system after extraction..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/pentaho-server/pentaho-solutions/system"
    echo "[DEBUG] Listing /opt/pentaho/pentaho-server/pentaho-solutions/system after extraction and chown..."
    docker exec -u 0 "$CONTAINER_ID" bash -c "ls -l /opt/pentaho/pentaho-server/pentaho-solutions/system"
fi
# You may need to adjust the cp command below after reviewing the debug output!
# cp step is now likely unnecessary, but keep debug fallback
docker exec -u 0 "$CONTAINER_ID" bash -c "cd /opt/pentaho/pentaho-server/pentaho-solutions/system && cp -r $PLUGIN_ZIP_FILENAME/pentaho-server/* /opt/pentaho/pentaho-server/ 2>/dev/null || echo '[DEBUG] cp command skipped, adjust path as needed.'"
docker exec -u 0 "$CONTAINER_ID" bash -c "rm -rf /opt/pentaho/pentaho-server/pentaho-solutions/system/karaf/caches/*"

echo "[DEBUG] Cleaning up temporary files..."
# Clean up the plugin zip from container /tmp
docker exec -u 0 "$CONTAINER_ID" bash -c "rm -f /tmp/$PLUGIN_ZIP_FILENAME"
# Clean up any extraction artifacts in /tmp
docker exec -u 0 "$CONTAINER_ID" bash -c "rm -rf /tmp/*plugin* /tmp/unzip* 2>/dev/null || true"
# Clean up the plugin zip from host staging dir
rm -f "$STAGING_DIR/$PLUGIN_ZIP_FILENAME" 2>/dev/null || true
echo "[DEBUG] Cleanup complete."

echo "[DEBUG] Restarting Pentaho container..."
docker restart "$CONTAINER_ID"
ENDSSH

echo "✅ Plugin installed and Pentaho server restarted on ${SSH_IP}"
echo "🧹 Temporary files cleaned up from host and container"