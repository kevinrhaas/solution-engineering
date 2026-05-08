#!/bin/bash
# 00-deploy.sh
# Deploy application to existing EC2 instance (runs 02-transfer-and-build.sh + 03-deploy-app.sh)

set -e

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
ENVIRONMENT=${1:-"prod"}  # Default to prod, can specify test

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "❌ Invalid environment name. Use alphanumeric characters, hyphens, or underscores"
    echo "Usage: $0 [environment]"
    echo "Examples:"
    echo "  $0 prod"
    echo "  $0 test"
    echo "  $0 dev"
    echo "  $0 staging"
    exit 1
fi

echo "🚀 Deploying application..."
echo "Environment: ${ENVIRONMENT}"
echo "Script Directory: ${SCRIPT_DIR}"
echo ""

# Check if instance info exists
INSTANCE_INFO="${SCRIPT_DIR}/instance-info-${ENVIRONMENT}.env"
if [ ! -f "${INSTANCE_INFO}" ]; then
    echo "❌ Instance info not found: ${INSTANCE_INFO}"
    echo "Please run 01-create-ec2-instance.sh first or use full-deploy.sh"
    exit 1
fi

echo "✅ Found instance config: ${INSTANCE_INFO}"

# Step 1: Transfer and build
echo ""
echo "📦 Step 1: Transfer files and build Docker image..."
echo "Running: ${SCRIPT_DIR}/02-transfer-and-build.sh ${ENVIRONMENT}"
"${SCRIPT_DIR}/02-transfer-and-build.sh" "${ENVIRONMENT}"

if [ $? -ne 0 ]; then
    echo "❌ Transfer and build failed"
    exit 1
fi

echo "✅ Transfer and build completed successfully"

# Step 2: Deploy application
echo ""
echo "🚀 Step 2: Deploy application..."
echo "Running: ${SCRIPT_DIR}/03-deploy-app.sh ${ENVIRONMENT}"
"${SCRIPT_DIR}/03-deploy-app.sh" "${ENVIRONMENT}"

if [ $? -ne 0 ]; then
    echo "❌ Application deployment failed"
    exit 1
fi

echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 SUMMARY:"
echo "   Environment: ${ENVIRONMENT}"
echo ""
echo "🔗 ACCESS:"
echo "   App: Check instance for port 80"
echo "   Health: Check instance health-check.sh"
echo ""
echo "💡 TIP: Run ./90-status.sh to check deployment status"
