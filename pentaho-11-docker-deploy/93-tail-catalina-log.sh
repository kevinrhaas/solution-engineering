#!/bin/bash

# ================================================================================================
# Tail Catalina Log
# ================================================================================================
# Usage: ./93-tail-catalina-log.sh <env-file> [lines]
# - env-file: required (e.g., pentaho-deployment-sample-204.env)
# - lines: optional, number of lines to tail (default: 200). Use "all" for full file.
# Examples:
#   ./93-tail-catalina-log.sh pentaho-deployment-sample-204.env
#   ./93-tail-catalina-log.sh pentaho-deployment-sample-204.env 500
#   ./93-tail-catalina-log.sh pentaho-deployment-sample-204.env all
# ================================================================================================

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file> [lines]"
    echo "Example: $0 pentaho-deployment-sample.env"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-113.env 500"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
TAIL_LINES="${2:-200}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state file: env var > newest match > legacy derivation
if [ -n "${STATE_FILE:-}" ]; then
    STATE_FILE_NAME="$(basename "$STATE_FILE")"
else
    _found=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
    STATE_FILE_NAME="${_found:+$(basename "$_found")}"
    STATE_FILE_NAME="${STATE_FILE_NAME:-${ENV_FILE_NAME%.env}-runtime.state}"
fi

# Load environment variables
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"
source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

# Resolve KEY_PATH to server-local key if original path doesn't exist
[ ! -f "$KEY_PATH" ] && KEY_PATH="$HOME/.ssh/$(basename "$KEY_PATH")"

# Ensure DB_TYPE available
DB_TYPE=${DB_TYPE:-postgres}
SSH_USER=${SSH_USER:-ubuntu}

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<ENDSSH
set -e
# Find the pentaho server container
CONTAINER_ID=\$(docker ps --format '{{.ID}} {{.Names}}' | grep -E "pentaho-server-${DB_TYPE}.*pentaho-server" | awk '{print \$1}')
if [ -z "\$CONTAINER_ID" ]; then
    echo "❌ Pentaho container not found!"
    docker ps --format 'table {{.Names}}\t{{.Status}}'
    exit 1
fi
echo "[DEBUG] Using container: \$CONTAINER_ID"
TAIL_LINES="${TAIL_LINES}"
if [ "\$TAIL_LINES" = "all" ]; then
    docker exec "\$CONTAINER_ID" bash -c "cd /opt/pentaho/pentaho-server/tomcat/logs && LATEST=\\\$(ls -1t catalina*.log 2>/dev/null | head -n1); echo '[DEBUG] Showing full file: \\\$LATEST'; cat \\\$LATEST"
else
    docker exec "\$CONTAINER_ID" bash -c "cd /opt/pentaho/pentaho-server/tomcat/logs && LATEST=\\\$(ls -1t catalina*.log 2>/dev/null | head -n1); echo '[DEBUG] Tailing \$TAIL_LINES lines: \\\$LATEST'; tail -n \$TAIL_LINES \\\$LATEST"
fi
ENDSSH
