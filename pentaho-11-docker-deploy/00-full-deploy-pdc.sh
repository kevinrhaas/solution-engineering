#!/bin/bash
# 00-full-deploy-pdc.sh
# Main wrapper script for complete PDC (Pentaho Data Catalog) deployment
# Orchestrates: EC2 creation -> readiness check -> PDC deployment

set -e

ENV_FILE_NAME="$(basename "${1}")"

# Validate environment parameter
if [ -z "$1" ]; then
    echo "❌ Environment file parameter required"
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pdc-10.2.10.env"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the environment file to get the actual ENVIRONMENT variable
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    echo "Available files:"
    ls -la "${SCRIPT_DIR}"/pdc-*.env 2>/dev/null || echo "None found"
    exit 1
fi
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"

echo "🚀 Full PDC Deployment Pipeline"
echo "================================"
echo "Environment File: ${ENV_FILE_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "PDC Version: ${PDC_VERSION}"
echo "Script Directory: ${SCRIPT_DIR}"
echo ""

# Helper: update DEPLOY_PHASE in state file
update_phase() {
    local phase="$1"
    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        if grep -q '^DEPLOY_PHASE=' "$STATE_FILE"; then
            sed -i.bak "s/^DEPLOY_PHASE=.*/DEPLOY_PHASE=${phase}/" "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
        else
            echo "DEPLOY_PHASE=${phase}" >> "$STATE_FILE"
        fi
    fi
}

# Step 1: Verify AWS authentication
echo "🔐 Step 1/4: Verifying AWS Authentication"
echo "------------------------------------------"
if ! "${SCRIPT_DIR}/01-auth-okta-aws.sh" "${ENV_FILE_NAME}"; then
    echo "❌ AWS authentication failed. Please authenticate and try again."
    exit 1
fi
echo ""

# Step 2: Create EC2 instance
echo "📦 Step 2/4: Creating EC2 Instance"
echo "-----------------------------------"
if ! "${SCRIPT_DIR}/02-create-ec2.sh" "${ENV_FILE_NAME}"; then
    echo "❌ Failed to create EC2 instance"
    exit 1
fi

# Discover the state file created by 02-create-ec2.sh (newest match for this profile)
STATE_FILE=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
if [ -z "$STATE_FILE" ]; then
    echo "❌ No runtime state file found after EC2 creation"
    exit 1
fi
STATE_FILE_NAME=$(basename "$STATE_FILE")
echo "📋 Using state file: ${STATE_FILE_NAME}"
export STATE_FILE
echo ""

# Step 3: Wait for EC2 to be ready
echo "⏳ Step 3/4: Waiting for EC2 to be ready"
echo "-----------------------------------------"

if [ ! -f "${SCRIPT_DIR}/03-check-ec2.sh" ]; then
    echo "⚠️  03-check-ec2.sh not found, waiting 60 seconds instead..."
    sleep 60
else
    MAX_ATTEMPTS=30
    ATTEMPT=1
    SLEEP_INTERVAL=20
    
    echo "Will check every ${SLEEP_INTERVAL} seconds (max ${MAX_ATTEMPTS} attempts)..."
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
        echo ""
        echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}:"
        
        if "${SCRIPT_DIR}/03-check-ec2.sh" "${ENV_FILE_NAME}" "${STATE_FILE_NAME}" 2>&1 | tee /tmp/check-output.txt; then
            if grep -q "✅.*ready\|✅.*Ready\|Instance is ready" /tmp/check-output.txt; then
                echo ""
                echo "✅ EC2 instance is ready!"
                rm -f /tmp/check-output.txt
                break
            fi
        fi
        
        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
            echo ""
            echo "⚠️  Max attempts reached. Proceeding anyway..."
            echo "   The instance may still be initializing."
            rm -f /tmp/check-output.txt
            break
        fi
        
        echo "   Waiting ${SLEEP_INTERVAL} seconds before next check..."
        sleep $SLEEP_INTERVAL
        ATTEMPT=$((ATTEMPT + 1))
    done
fi
echo ""
update_phase "ec2-ready"

# Step 4: Deploy PDC
echo "🎯 Step 4/4: Deploying PDC"
echo "---------------------------"
if ! "${SCRIPT_DIR}/30-deploy-pdc.sh" "${ENV_FILE_NAME}"; then
    echo "❌ Failed to deploy PDC"
    exit 1
fi
update_phase "pdc-deployed"
echo ""

echo "🎉 Full PDC Deployment Complete!"
echo "================================="
echo ""
echo "Next steps:"
echo "  1. Access PDC at https://<instance-ip>"
echo "     (Self-signed certificate — browser will show a security warning)"
echo "  2. Login with default credentials"
echo ""
echo "To teardown:"
echo "  ./99-teardown.sh ${ENV_FILE_NAME}"
echo ""
