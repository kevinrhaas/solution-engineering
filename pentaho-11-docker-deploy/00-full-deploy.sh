#!/bin/bash
# deploy-pentaho.sh
# Main wrapper script for complete Pentaho deployment
# Orchestrates: EC2 creation -> readiness check -> Pentaho deployment

set -e

ENV_FILE_NAME="$(basename "${1}")"

# Validate environment parameter
if [ -z "$1" ]; then
    echo "❌ Environment file parameter required"
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-dev.env"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-113.env"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the environment file to get the actual ENVIRONMENT variable
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    echo "Available files:"
    ls -la "${SCRIPT_DIR}"/pentaho-deployment-*.env 2>/dev/null || echo "None found"
    exit 1
fi
source "${SCRIPT_DIR}/${ENV_FILE_NAME}"

echo "🚀 Full Pentaho Deployment Pipeline"
echo "===================================="
echo "Environment File: ${ENV_FILE_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Script Directory: ${SCRIPT_DIR}"
echo "Plugin Deployment: ${DEPLOY_PLUGINS:-yes}"
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
echo "🔐 Step 1/5: Verifying AWS Authentication"
echo "------------------------------------------"
if ! "${SCRIPT_DIR}/01-auth-okta-aws.sh" "${ENV_FILE_NAME}"; then
    echo "❌ AWS authentication failed. Please authenticate and try again."
    exit 1
fi
echo ""

# Step 2: Create EC2 instance
echo "📦 Step 2/5: Creating EC2 Instance"
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
echo "⏳ Step 3/5: Waiting for EC2 to be ready"
echo "-----------------------------------------"

# Check if 03 script exists
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
            # Check if the output indicates readiness
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

# Step 3: Deploy Pentaho
echo "🎯 Step 3/4: Deploying Pentaho"
echo "-------------------------------"
if ! "${SCRIPT_DIR}/10-deploy-pentaho.sh" "${ENV_FILE_NAME}"; then
    echo "❌ Failed to deploy Pentaho"
    exit 1
fi
update_phase "pentaho-deployed"
echo ""

# Step 4: Deploy Plugins (optional, controlled by DEPLOY_PLUGINS variable)
if [ "${DEPLOY_PLUGINS:-yes}" = "yes" ]; then
    echo "🔌 Step 4/4: Installing All Plugins"
    echo "------------------------------------"
    if ! "${SCRIPT_DIR}/20-deploy-all-plugins.sh" "${ENV_FILE_NAME}" "${STATE_FILE_NAME}"; then
        echo "⚠️  Plugin installation failed, but Pentaho is deployed"
        echo "   You can install plugins manually later with:"
        echo "   ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
    else
        update_phase "plugins-deployed"
    fi
    echo ""
else
    echo "⏭️  Step 4/4: Skipping Plugin Installation (DEPLOY_PLUGINS=no)"
    echo "--------------------------------------------------------------"
    update_phase "pentaho-deployed"
    echo "   To install plugins later, run:"
    echo "   ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
    echo ""
fi

echo "🎉 Full Deployment Complete!"
echo "============================="
echo ""
echo "Next steps:"
echo "  1. Access Pentaho at the URL shown above"
echo "  2. Login with admin/password"
echo "  3. Check license installation in Administration > Licenses"
echo ""
if [ "${DEPLOY_PLUGINS:-yes}" != "yes" ]; then
    echo "To install plugins:"
    echo "  ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
    echo ""
fi
echo "To teardown:"
echo "  ./99-teardown.sh ${ENV_FILE_NAME}"
echo ""
