#!/bin/bash

# teardown-instance.sh
# Tear down the existing Pentaho EC2 instance to start fresh

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

# Configuration
ENV_FILE_NAME="$(basename "${1:-pentaho-deployment-dev.env}")"

# Source environment configuration
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

# Source input configuration
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Environment file not found: ${ENV_FILE_NAME}"
    echo "Usage: $0 <env-file>"
    exit 1
fi
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"

# Source runtime state (contains instance information)
RUNTIME_STATE="${SCRIPT_DIR}/${STATE_FILE_NAME}"
if [ ! -f "${RUNTIME_STATE}" ]; then
    echo "❌ No runtime state file found: ${STATE_FILE_NAME}"
    echo "No instance to tear down for environment: ${ENVIRONMENT}"
    exit 0
fi
source "${RUNTIME_STATE}"

echo "🗑️  Tearing Down Pentaho Instance - ${ENVIRONMENT}"
echo "==========================================="
echo "📍 Instance ID: ${INSTANCE_ID}"
echo "📍 Environment: ${ENVIRONMENT}"
echo ""

# Check if instance exists and get its state
echo "🔍 Checking instance status..."
INSTANCE_STATE=$(aws_cmd ${AWS_PROFILE} ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "not-found")

if [ "$INSTANCE_STATE" = "not-found" ]; then
    echo "✅ Instance ${INSTANCE_ID} not found or already terminated"
    echo ""
    echo "🧹 Cleaning up local state files..."
    if [ -f "${STATE_FILE_NAME}" ]; then
        rm "${STATE_FILE_NAME}"
        echo "✅ Removed runtime state file"
    fi
    echo ""
    echo "🎯 Ready to create fresh instance:"
    echo "   ./02-create-ec2.sh ${ENV_FILE_NAME}"
    exit 0
fi

echo "📊 Current instance state: ${INSTANCE_STATE}"

if [ "$INSTANCE_STATE" = "terminated" ]; then
    echo "✅ Instance is already terminated"
    echo ""
    echo "🧹 Cleaning up local state files..."
    if [ -f "${STATE_FILE_NAME}" ]; then
        rm "${STATE_FILE_NAME}"
        echo "✅ Removed runtime state file"
    fi
    echo ""
    echo "🎯 Ready to create fresh instance:"
    echo "   ./02-create-ec2.sh ${ENV_FILE_NAME}"
    exit 0
fi

# Get instance IP information for display
echo "🔍 Getting instance information..."
INSTANCE_INFO=$(aws_cmd ${AWS_PROFILE} ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress}' \
    --output json 2>/dev/null || echo '{"PublicIp": null, "PrivateIp": null}')

PUBLIC_IP=$(echo ${INSTANCE_INFO} | jq -r '.PublicIp // "No public IP"')
INSTANCE_PRIVATE_IP=$(echo ${INSTANCE_INFO} | jq -r '.PrivateIp // "No private IP"')

echo ""
echo "⚠️  This will PERMANENTLY DELETE the EC2 instance and all data!"
echo "   Instance: ${INSTANCE_ID} (${INSTANCE_STATE})"
echo "   Public IP: ${PUBLIC_IP}"
echo "   Private IP: ${INSTANCE_PRIVATE_IP}"
echo ""

read -p "Are you sure you want to proceed? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "❌ Teardown cancelled"
    exit 0
fi

echo ""
echo "🛑 Terminating EC2 instance..."

# Terminate the instance
if aws_cmd ${AWS_PROFILE} ec2 terminate-instances --region ${AWS_REGION} --instance-ids ${INSTANCE_ID}; then
    echo "✅ Instance termination initiated"
    
    echo ""
    echo "⏳ Waiting for instance to terminate..."
    echo "   This may take 1-2 minutes..."
    
    # Wait for termination with timeout
    timeout=120  # 2 minutes
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        CURRENT_STATE=$(aws_cmd ${AWS_PROFILE} ec2 describe-instances \
            --region ${AWS_REGION} \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        
        if [ "$CURRENT_STATE" = "terminated" ]; then
            echo "✅ Instance ${INSTANCE_ID} terminated successfully"
            break
        fi
        
        echo "   Status: ${CURRENT_STATE}... waiting..."
        sleep 15
        elapsed=$((elapsed + 15))
    done
    
    # Clean up local state files
    echo ""
    echo "🧹 Cleaning up local state files..."
    if [ -f "${STATE_FILE_NAME}" ]; then
        rm "${STATE_FILE_NAME}"
        echo "✅ Removed runtime state file"
    fi
    
    echo ""
    echo "✅ Teardown completed successfully!"
    echo ""
    echo "🔄 Ready to create fresh instance:"
    echo "   Full deployment: ./00-full-deploy.sh ${ENV_FILE_NAME}"
    echo "   Or step-by-step:"
    echo "     1. ./02-create-ec2.sh ${ENV_FILE_NAME}"
    echo "     2. ./10-deploy-pentaho.sh ${ENV_FILE_NAME}"
    echo "     3. ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
    
else
    echo "❌ Failed to terminate instance"
    echo ""
    echo "🔧 Manual termination required:"
    echo "   1. Go to AWS EC2 Console"
    echo "   2. Find instance: ${INSTANCE_ID}"
    echo "   3. Right-click → Instance State → Terminate"
fi

echo ""
echo "📝 Note: The updated scripts use proper configuration management"
echo "   External access should work immediately after deployment!"
