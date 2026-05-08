#!/bin/bash

# ================================================================================================
# Get Docker Container Logs
# ================================================================================================
# This script retrieves logs from a Docker container running on an EC2 instance
# Usage: ./94-get-docker-logs.sh <env-file> [container-name] [duration] [db-type]
# - env-file: required (e.g., pentaho-deployment-sample-204.env)
# - container-name: optional. If omitted, auto-detects using db-type
# - duration: optional, e.g. 10m, 1h, 30s. If omitted, streams all available logs
# - db-type: optional. Defaults to 'postgres'. Can also be set via PENTAHO_DB_TYPE env
# Examples:
#   ./94-get-docker-logs.sh pentaho-deployment-sample-204.env
#   ./94-get-docker-logs.sh pentaho-deployment-sample-204.env "pentaho-server-postgres-pentaho-server-1"
#   ./94-get-docker-logs.sh pentaho-deployment-sample-204.env "" 10m
#   ./94-get-docker-logs.sh sample-204 "" 10m mysql
# ================================================================================================

if [ $# -lt 1 ]; then
        echo "Usage: $0 <env-file> [container-name] [duration] [db-type]"
    echo ""
    echo "Arguments:"
        echo "  env-file       - Required. Environment file (e.g., pentaho-deployment-sample-204.env)"
        echo "  container-name - Optional. Specific container name. If not provided, auto-detects based on db-type"
        echo "  duration       - Optional. Time duration for logs (e.g., 10m, 1h, 30s). If not provided, dumps all logs"
        echo "  db-type        - Optional. One of postgres (default), mysql, sqlserver, oracle"
    echo ""
    echo "Examples:"
        echo "  $0 pentaho-deployment-sample-204.env                                              # Get all logs from default pentaho container"
        echo "  $0 pentaho-deployment-sample-204.env pentaho-server-postgres-pentaho-server-1    # Get all logs from specific container"
        echo "  $0 pentaho-deployment-sample-204.env '' 10m mysql                                # Get last 10 minutes using MySQL container"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
CONTAINER_NAME="${2:-}"
DURATION="${3:-}"
# Database type: default to 'postgres'; allow override via env or 4th arg
DB_TYPE="postgres"
if [ -n "${PENTAHO_DB_TYPE:-}" ]; then
    DB_TYPE="${PENTAHO_DB_TYPE}"
fi
if [ -n "${4:-}" ]; then
    DB_TYPE="${4}"
fi

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

# Resolve KEY_PATH to server-local key if original path doesn't exist
[ ! -f "$KEY_PATH" ] && KEY_PATH="$HOME/.ssh/$(basename "$KEY_PATH")"

SSH_USER=${SSH_USER:-ubuntu}

echo "================================================================================================"
echo "Retrieving Docker Container Logs"
echo "================================================================================================"
echo "Environment:    ${ENVIRONMENT}"
echo "EC2 Instance:   ${INSTANCE_ID} (${SSH_IP})"
echo "Container:      ${CONTAINER_NAME:-<auto-detect>}"
echo "Duration:       ${DURATION:-<all logs>}"
echo "DB Type:        ${DB_TYPE}"
echo "================================================================================================"
echo ""

# Build the docker logs command with optional parameters
if [ -n "$CONTAINER_NAME" ] && [ -n "$DURATION" ]; then
    DOCKER_LOGS_CMD="docker logs --since ${DURATION} \${CONTAINER_NAME}"
    DESCRIPTION="Getting logs from last ${DURATION} for container: ${CONTAINER_NAME}"
elif [ -n "$CONTAINER_NAME" ]; then
    DOCKER_LOGS_CMD="docker logs \${CONTAINER_NAME}"
    DESCRIPTION="Getting all logs for container: ${CONTAINER_NAME}"
elif [ -n "$DURATION" ]; then
    DOCKER_LOGS_CMD="docker logs --since ${DURATION} \${CONTAINER_NAME}"
    DESCRIPTION="Getting logs from last ${DURATION} for auto-detected pentaho container"
else
    DOCKER_LOGS_CMD="docker logs \${CONTAINER_NAME}"
    DESCRIPTION="Getting all logs for auto-detected pentaho container"
fi

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<ENDSSH
set -e

# Determine container name if not provided
if [ -n "${CONTAINER_NAME}" ]; then
    CONTAINER_NAME="${CONTAINER_NAME}"
else
    echo "🔍 Auto-detecting Pentaho container..."
    # Prefer the DB-specific pentaho server container naming pattern, then fall back
    CONTAINER_NAME=\$(docker ps --format '{{.Names}}' | grep -i "pentaho-server-${DB_TYPE}-pentaho-server" | head -n1)
    if [ -z "\$CONTAINER_NAME" ]; then
        CONTAINER_NAME=\$(docker ps --format '{{.Names}}' | grep -i pentaho | head -n1)
    fi
    
    if [ -z "\$CONTAINER_NAME" ]; then
        echo "❌ No running Pentaho container found!"
        echo ""
        echo "Available containers:"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        exit 1
    fi
    echo "✅ Found container: \$CONTAINER_NAME"
    echo ""
fi

# Verify container exists
if ! docker ps --format '{{.Names}}' | grep -q "^\${CONTAINER_NAME}\$"; then
    echo "❌ Container '\$CONTAINER_NAME' not found or not running!"
    echo ""
    echo "Available containers:"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    exit 1
fi

echo "================================================================================================"
echo "${DESCRIPTION}"
echo "================================================================================================"
echo ""

# Execute docker logs command
${DOCKER_LOGS_CMD}

ENDSSH

EXIT_CODE=$?

echo ""
echo "================================================================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Successfully retrieved Docker logs from ${SSH_IP}"
else
    echo "❌ Failed to retrieve Docker logs (exit code: $EXIT_CODE)"
fi
echo "================================================================================================"

exit $EXIT_CODE
