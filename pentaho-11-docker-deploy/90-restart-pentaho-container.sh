#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-sample.env"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-113.env"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state file: explicit arg > env var > newest match > legacy derivation
if [ -n "${2:-}" ]; then
    STATE_FILE_NAME="$(basename "$2")"
elif [ -n "${STATE_FILE:-}" ]; then
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

COMPOSE_DIR="/home/${SSH_USER}/pentaho/onprem/dist/on-prem/pentaho-server/pentaho-server-${DB_TYPE}"
COMPOSE_FILE="docker-compose-${DB_TYPE}.yaml"

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<ENDSSH
set -e
cd "${COMPOSE_DIR}"
echo "[DEBUG] Ensuring database is running..."
docker compose -f "${COMPOSE_FILE}" up -d repository 2>/dev/null || docker compose -f "${COMPOSE_FILE}" up -d ${DB_TYPE} 2>/dev/null || true
echo "[DEBUG] Restarting Pentaho server..."
docker compose -f "${COMPOSE_FILE}" restart pentaho-server

if [ "${ENVIRONMENT}" = "ops-console" ]; then
    echo "[DEBUG] Ops-console mode: patching ROOT redirect to :8000..."
    CID=\$(docker compose -f "${COMPOSE_FILE}" ps -q pentaho-server | head -1)
    if [ -n "\$CID" ]; then
        docker exec "\$CID" sh -lc 'cat > /opt/pentaho/pentaho-server/tomcat/webapps/ROOT/index.jsp << "EOF"
<%
String scheme = request.getScheme();
String host = request.getServerName();
String target = scheme + "://" + host + ":8000/";
response.sendRedirect(target);
%>
EOF'
        echo "[DEBUG] ROOT redirect patched"
    else
        echo "[WARN] pentaho-server container not found; skipped redirect patch"
    fi
fi

echo ""
echo "[DEBUG] Container status:"
docker compose -f "${COMPOSE_FILE}" ps
ENDSSH

echo "✅ Pentaho container restarted on ${SSH_IP}"
