#!/bin/bash

# ================================================================================================
# SSH into EC2 Instance
# ================================================================================================
# This script opens an SSH session to the EC2 instance
# Usage: ./96-ssh-into-instance.sh <env-file>
# Example: ./96-ssh-into-instance.sh pentaho-deployment-sample-204.env
# ================================================================================================

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo ""
    echo "Arguments:"
    echo "  env-file - Required. Environment file (e.g., pentaho-deployment-sample-204.env)"
    echo ""
    echo "Example:"
    echo "  $0 pentaho-deployment-sample-204.env"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
STATE_FILE_NAME="${ENV_FILE_NAME%.env}-runtime.state"

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
echo "SSH into EC2 Instance"
echo "================================================================================================"
echo "Environment:    ${ENVIRONMENT}"
echo "EC2 Instance:   ${INSTANCE_ID} (${SSH_IP})"
echo "User:           ${SSH_USER}"
echo "================================================================================================"
echo ""

ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${SSH_IP}
