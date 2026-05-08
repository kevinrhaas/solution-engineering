#!/bin/bash

# Restart PDC Docker Compose services (pdc.sh down + pdc.sh up)

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pdc-10.2.10.env"
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

[ ! -f "$KEY_PATH" ] && KEY_PATH="$HOME/.ssh/$(basename "$KEY_PATH")"
SSH_USER=${SSH_USER:-ubuntu}

echo "🔄 Restarting PDC services on ${SSH_IP}..."
echo ""

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<'ENDSSH'
set -e
PDC_DIR="/opt/pentaho/pdc-docker-deployment"

if [ ! -d "$PDC_DIR" ]; then
    echo "❌ PDC deployment not found at $PDC_DIR"
    exit 1
fi

cd "$PDC_DIR"

if [ ! -f pdc.sh ]; then
    echo "❌ pdc.sh not found in $PDC_DIR"
    exit 1
fi

if [ -f conf/.env ]; then
    licensing_server_url="$(grep -E '^LICENSING_SERVER_URL=' conf/.env | tail -1 | cut -d= -f2-)"
    pdi_license_url="$(grep -E '^PDI_LICENSE_URL=' conf/.env | tail -1 | cut -d= -f2-)"
    if [ -n "${licensing_server_url}" ] && [ -z "${pdi_license_url}" ]; then
        echo "🛠️  Adding missing PDI_LICENSE_URL from LICENSING_SERVER_URL"
        echo "PDI_LICENSE_URL=${licensing_server_url}" | sudo tee -a conf/.env >/dev/null
    fi
fi

echo "📋 Current container status:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -20 || true
echo ""

echo "⏹️  Stopping PDC services (pdc.sh stop)..."
sudo bash pdc.sh stop 2>&1
echo ""

echo "▶️  Starting PDC services (pdc.sh up)..."
sudo bash pdc.sh up 2>&1
echo ""

echo "📋 Container status after restart:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -20 || true
echo ""

echo "✅ PDC services restarted!"
ENDSSH

echo ""
echo "✅ PDC restart complete on ${SSH_IP}"
