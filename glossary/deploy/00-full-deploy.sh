#!/bin/bash
# 00-full-deploy.sh
# Complete deployment: Create EC2 instance + Deploy application (runs 01 + 02 + 03)

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

echo "🚀 Full deployment starting..."
echo "Environment: ${ENVIRONMENT}"
echo "Script Directory: ${SCRIPT_DIR}"
echo ""

# Check if instance already exists
INSTANCE_INFO="${SCRIPT_DIR}/instance-info-${ENVIRONMENT}.env"
if [ -f "${INSTANCE_INFO}" ]; then
    echo "⚠️  Instance config already exists: ${INSTANCE_INFO}"
    echo "This will create a NEW instance. Continue? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled"
        echo "💡 TIP: Use ./deploy.sh to deploy to existing instance"
        exit 1
    fi
    echo "🗑️  Backing up existing config..."
    mv "${INSTANCE_INFO}" "${INSTANCE_INFO}.backup.$(date +%s)"
fi

# Step 1: Create EC2 instance
echo ""
echo "🖥️  Step 1: Create EC2 instance..."
echo "Running: ${SCRIPT_DIR}/01-create-ec2-instance.sh ${ENVIRONMENT}"
"${SCRIPT_DIR}/01-create-ec2-instance.sh" "${ENVIRONMENT}"

if [ $? -ne 0 ]; then
    echo "❌ EC2 instance creation failed"
    exit 1
fi

echo "✅ EC2 instance created successfully"

# Wait a moment for instance to fully initialize
echo "⏳ Waiting 30 seconds for instance to fully initialize..."
sleep 30

# Step 2: Transfer and build
echo ""
echo "📦 Step 2: Transfer files and build Docker image..."
echo "Running: ${SCRIPT_DIR}/02-transfer-and-build.sh ${ENVIRONMENT}"
"${SCRIPT_DIR}/02-transfer-and-build.sh" "${ENVIRONMENT}"

if [ $? -ne 0 ]; then
    echo "❌ Transfer and build failed"
    echo "💡 TIP: You can retry with ./deploy.sh ${ENVIRONMENT}"
    exit 1
fi

echo "✅ Transfer and build completed successfully"

# Step 3: Deploy application
echo ""
echo "🚀 Step 3: Deploy application..."
echo "Running: ${SCRIPT_DIR}/03-deploy-app.sh ${ENVIRONMENT}"
"${SCRIPT_DIR}/03-deploy-app.sh" "${ENVIRONMENT}"

if [ $? -ne 0 ]; then
    echo "❌ Application deployment failed"
    echo "💡 TIP: You can retry with ./deploy.sh ${ENVIRONMENT}"
    exit 1
fi

echo ""
echo "🎉 Full deployment completed successfully!"
echo ""
echo "📋 SUMMARY:"
echo "   Environment: ${ENVIRONMENT} (newly created)"
echo ""

# Show instance info if available
if [ -f "${INSTANCE_INFO}" ]; then
    source "${INSTANCE_INFO}"
    echo "🔗 ACCESS:"
    echo "   Instance ID: ${INSTANCE_ID}"
    echo "   Private IP: ${PRIVATE_IP}"
    echo "   App: ${APP_URL}"
    echo "   Health: ${HEALTH_URL}"
    echo ""
    echo "🔑 SSH ACCESS:"
    echo "   ${SSH_COMMAND}"
fi

echo ""
echo "💡 NEXT STEPS:"
echo "   • Check status: ./90-status.sh"
echo "   • View logs: SSH to instance and run 'docker logs glossary-app'"
echo "   • Redeploy: ./deploy.sh ${ENVIRONMENT}"
echo "   • Cleanup: ./99-cleanup.sh ${ENVIRONMENT}"
