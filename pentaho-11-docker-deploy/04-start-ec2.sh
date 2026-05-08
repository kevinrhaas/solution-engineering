#!/bin/bash

# Start an existing EC2 instance from runtime state

set -e

# Detect environment: local Mac vs remote server
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

# Upsert a KEY=VALUE pair in runtime state file
upsert_state_var() {
    local file="$1"
    local key="$2"
    local val="$3"
    local tmp
    tmp="${file}.tmp"

    awk -v key="$key" -v val="$val" '
    BEGIN { replaced = 0 }
    {
        if ($0 ~ ("^" key "=")) {
            print key "=" val
            replaced = 1
        } else {
            print
        }
    }
    END {
        if (!replaced) {
            print key "=" val
        }
    }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# Configuration
ENV_FILE_NAME="$(basename "${1:-pentaho-deployment-dev.env}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

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

# Load env + runtime
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Environment file not found: ${ENV_FILE_NAME}"
    exit 1
fi
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"

RUNTIME_STATE="${SCRIPT_DIR}/${STATE_FILE_NAME}"
if [ ! -f "${RUNTIME_STATE}" ]; then
    echo "❌ Runtime state not found: ${STATE_FILE_NAME}"
    echo "Run 02-create-ec2.sh first or provide STATE_FILE."
    exit 1
fi
source "${RUNTIME_STATE}"

if [ -z "${INSTANCE_ID:-}" ]; then
    echo "❌ INSTANCE_ID missing in runtime state: ${STATE_FILE_NAME}"
    exit 1
fi

echo "🚀 Starting EC2 instance"
echo "Instance: ${INSTANCE_ID}"
echo "Profile:  ${ENV_FILE_NAME}"

echo "🔍 Checking current instance state..."
CURRENT_STATE=$(aws_cmd ${AWS_PROFILE} ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "not-found")

echo "Current state: ${CURRENT_STATE}"

if [ "${CURRENT_STATE}" = "not-found" ] || [ "${CURRENT_STATE}" = "terminated" ] || [ "${CURRENT_STATE}" = "shutting-down" ]; then
    echo "❌ Instance cannot be started from state: ${CURRENT_STATE}"
    exit 1
fi

if [ "${CURRENT_STATE}" = "running" ]; then
    echo "✅ Instance is already running"
else
    echo "⏳ Starting instance..."
    aws_cmd ${AWS_PROFILE} ec2 start-instances \
        --region ${AWS_REGION} \
        --instance-ids ${INSTANCE_ID} >/dev/null

    echo "⏳ Waiting for running state..."
    aws_cmd ${AWS_PROFILE} ec2 wait instance-running \
        --region ${AWS_REGION} \
        --instance-ids ${INSTANCE_ID}
fi

INSTANCE_INFO=$(aws_cmd ${AWS_PROFILE} ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,State.Name]' \
    --output text)

PUBLIC_IP=$(echo "${INSTANCE_INFO}" | awk '{print $1}')
PRIVATE_IP=$(echo "${INSTANCE_INFO}" | awk '{print $2}')
FINAL_STATE=$(echo "${INSTANCE_INFO}" | awk '{print $3}')

if [ "${PUBLIC_IP}" = "None" ]; then PUBLIC_IP=""; fi
if [ "${PRIVATE_IP}" = "None" ]; then PRIVATE_IP=""; fi
if [ -z "${FINAL_STATE}" ] || [ "${FINAL_STATE}" = "None" ]; then FINAL_STATE="running"; fi

upsert_state_var "${RUNTIME_STATE}" "INSTANCE_STATE" "${FINAL_STATE}"
upsert_state_var "${RUNTIME_STATE}" "PUBLIC_IP" "${PUBLIC_IP}"
upsert_state_var "${RUNTIME_STATE}" "PRIVATE_IP" "${PRIVATE_IP}"

echo "✅ Instance started"
echo "State:      ${FINAL_STATE}"
echo "Public IP:  ${PUBLIC_IP:-none}"
echo "Private IP: ${PRIVATE_IP:-none}"
