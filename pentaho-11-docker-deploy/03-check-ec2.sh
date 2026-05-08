#!/bin/bash

# Check if Pentaho EC2 instance is ready for deployment
# Usage: ./03-check-ec2.sh <env-file>

set -e

# ============================================================
# Detect environment: local Mac vs remote server
# ============================================================
if [[ "$(uname)" == "Darwin" ]]; then
    RUN_MODE="local"
    # Source shell configuration to get okta-aws function
    if [ -f ~/.zshrc ]; then
        source ~/.zshrc
    elif [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi
else
    RUN_MODE="server"
fi

# Helper: run an AWS CLI command using okta-aws (local) or aws --profile (server)
aws_cmd() {
    local profile="$1"
    shift
    if [ "$RUN_MODE" = "local" ]; then
        okta-aws "$profile" "$@"
    else
        aws --profile "$profile" "$@"
    fi
}

# Helper: resolve KEY_PATH for the current environment
resolve_key_path() {
    local kp="$1"
    if [ "$RUN_MODE" = "server" ]; then
        local basename
        basename="$(basename "$kp")"
        echo "$HOME/.ssh/$basename"
    else
        echo "$kp"
    fi
}

# Configuration
ENV_FILE_NAME="$(basename "${1:-pentaho-deployment-sample-11-1-0-0-120.env}")"

# Get script directory
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

# Load configuration
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    exit 1
fi
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"

# Load runtime state
if [ ! -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ Error: Runtime state not found: ${STATE_FILE_NAME}"
    echo "Run ./02-create-ec2.sh ${ENV_FILE_NAME} first."
    exit 1
fi
source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

echo "🔍 Checking Pentaho EC2 Instance Status"
echo "========================================"
echo "Environment: ${ENVIRONMENT}"
echo "Instance ID: ${INSTANCE_ID}"
echo ""

# Check instance state
echo "📋 Checking AWS instance state..."
INSTANCE_STATE=$(aws_cmd "${AWS_PROFILE}" ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "not-found")

if [ "${INSTANCE_STATE}" = "not-found" ]; then
    echo "❌ Instance not found in AWS"
    exit 1
elif [ "${INSTANCE_STATE}" != "running" ]; then
    echo "⚠️  Instance state: ${INSTANCE_STATE}"
    echo "   Instance must be 'running' to proceed"
    exit 1
fi

echo "✅ Instance state: ${INSTANCE_STATE}"

# Check instance status checks
echo ""
echo "📋 Checking instance status checks..."
STATUS_CHECKS=$(aws_cmd "${AWS_PROFILE}" ec2 describe-instance-status \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]' \
    --output text 2>/dev/null || echo "initializing initializing")

SYSTEM_STATUS=$(echo "${STATUS_CHECKS}" | awk '{print $1}')
INSTANCE_STATUS=$(echo "${STATUS_CHECKS}" | awk '{print $2}')

if [ "${SYSTEM_STATUS}" = "initializing" ] || [ "${INSTANCE_STATUS}" = "initializing" ]; then
    echo "⏳ Status checks still initializing..."
    echo "   System Status: ${SYSTEM_STATUS}"
    echo "   Instance Status: ${INSTANCE_STATUS}"
    echo "   Wait a few more minutes and try again"
    exit 1
elif [ "${SYSTEM_STATUS}" != "ok" ] || [ "${INSTANCE_STATUS}" != "ok" ]; then
    echo "⚠️  Status checks not OK:"
    echo "   System Status: ${SYSTEM_STATUS}"
    echo "   Instance Status: ${INSTANCE_STATUS}"
    exit 1
fi

echo "✅ System Status: ${SYSTEM_STATUS}"
echo "✅ Instance Status: ${INSTANCE_STATUS}"

# Check SSH connectivity
echo ""
echo "📋 Checking SSH connectivity..."
if [ -z "${SSH_IP}" ]; then
    echo "❌ SSH_IP not found in runtime state"
    exit 1
fi

# Test SSH connection with timeout
if ssh -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 \
    -o BatchMode=yes \
    ${SSH_USER}@${SSH_IP} \
    "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "✅ SSH connection: OK"
else
    echo "❌ SSH connection failed"
    echo "   Host: ${SSH_USER}@${SSH_IP}"
    echo "   Key: ${KEY_PATH}"
    echo ""
    echo "   Possible causes:"
    echo "   - Instance still initializing (wait 1-2 more minutes)"
    echo "   - Security group not allowing SSH from your IP"
    echo "   - Key pair mismatch"
    exit 1
fi

# Check if Docker is installed
echo ""
echo "📋 Checking Docker installation..."
if ssh -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=no \
    ${SSH_USER}@${SSH_IP} \
    "docker --version" >/dev/null 2>&1; then
    DOCKER_VERSION=$(ssh -i "${KEY_PATH}" \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${SSH_IP} \
        "docker --version" 2>/dev/null)
    echo "✅ Docker installed: ${DOCKER_VERSION}"
else
    echo "⚠️  Docker not installed or not ready"
    echo "   Wait for user-data script to complete (usually 2-3 minutes after launch)"
    exit 1
fi

# Check if Docker is running
echo ""
echo "📋 Checking Docker service status..."
if ssh -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=no \
    ${SSH_USER}@${SSH_IP} \
    "sudo systemctl is-active docker" >/dev/null 2>&1; then
    echo "✅ Docker service: running"
else
    echo "❌ Docker service not running"
    exit 1
fi

# Check available disk space
echo ""
echo "📋 Checking disk space..."
DISK_USAGE=$(ssh -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=no \
    ${SSH_USER}@${SSH_IP} \
    "df -h / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null)

if [ "${DISK_USAGE}" -gt 80 ]; then
    echo "⚠️  Disk usage: ${DISK_USAGE}% (high)"
else
    echo "✅ Disk usage: ${DISK_USAGE}%"
fi

# Check if pentaho directory exists
echo ""
echo "📋 Checking working directory..."
if ssh -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=no \
    ${SSH_USER}@${SSH_IP} \
    "test -d /home/${SSH_USER}/pentaho" 2>/dev/null; then
    echo "✅ Working directory exists: /home/${SSH_USER}/pentaho"
else
    echo "⚠️  Creating working directory: /home/${SSH_USER}/pentaho"
    ssh -i "${KEY_PATH}" \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${SSH_IP} \
        "mkdir -p /home/${SSH_USER}/pentaho" 2>/dev/null
    echo "✅ Working directory created"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Instance is ready for deployment!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Instance Details:"
echo "   Environment: ${ENVIRONMENT}"
echo "   Instance ID: ${INSTANCE_ID}"
echo "   IP Address: ${SSH_IP}"
echo "   SSH Command: ssh -i ${KEY_PATH} ${SSH_USER}@${SSH_IP}"
echo ""
echo "🚀 Next Step:"
echo "   ./10-deploy-pentaho.sh ${ENV_FILE_NAME}"
echo ""

exit 0
