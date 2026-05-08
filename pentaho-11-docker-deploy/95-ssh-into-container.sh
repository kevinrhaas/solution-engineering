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

# ================================================================================================
# Shell into Docker Container
# ================================================================================================
# This script opens an interactive shell inside a Docker container running on an EC2 instance
# Usage: ./95-shell-into-container.sh <env-file> [container-name] [db-type]
# Example: ./95-shell-into-container.sh pentaho-deployment-sample-204.env
# Example: ./95-shell-into-container.sh pentaho-deployment-sample-204.env pentaho-server-postgres-pentaho-server-1
# Example: ./95-shell-into-container.sh pentaho-deployment-sample-204.env "" mysql
# ================================================================================================

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file> [container-name] [db-type]"
    echo ""
    echo "Arguments:"
    echo "  env-file       - Required. Environment file (e.g., pentaho-deployment-sample-204.env)"
    echo "  container-name - Optional. Specific container name. If not provided, will auto-detect based on db-type"
    echo "  db-type        - Optional. Database type (postgres, mysql, sqlserver, oracle). Default: postgres"
    echo ""
    echo "Examples:"
    echo "  $0 pentaho-deployment-sample-204.env                                              # Shell into default postgres container"
    echo "  $0 pentaho-deployment-sample-204.env \"\" mysql                                     # Shell into mysql container (auto-detect name)"
    echo "  $0 pentaho-deployment-sample-204.env pentaho-server-postgres-pentaho-server-1    # Shell into specific container"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
STATE_FILE_NAME="${ENV_FILE_NAME%.env}-runtime.state"
CONTAINER_NAME="${2:-pentaho-server-${DB_TYPE}-pentaho-server-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Environment file not found: ${ENV_FILE_NAME}"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ Runtime state file not found: ${STATE_FILE_NAME}"
    echo "   Have you created the EC2 instance for this environment?"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"
source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

SSH_USER=${SSH_USER:-ubuntu}

echo "================================================================================================"
echo "Opening Shell in Docker Container"
echo "================================================================================================"
echo "Environment:    ${ENVIRONMENT}"
echo "EC2 Instance:   ${INSTANCE_ID} (${SSH_IP})"
echo "Database Type:  ${DB_TYPE}"
echo "Container:      ${CONTAINER_NAME}"
echo "================================================================================================"
echo ""

ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" -t ${SSH_USER}@${SSH_IP} \
  "docker exec -it ${CONTAINER_NAME} bash"
