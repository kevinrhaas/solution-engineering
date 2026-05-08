#!/bin/bash
# 04-deploy-app.sh
# Deploy the glossary app to EC2 instance

set -e

# Source shell configuration to get okta-aws function
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
elif [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# Configuration
ENVIRONMENT=${1:-"prod"}  # Which instance to deploy to (test|prod|dev|staging|etc)

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "❌ Invalid environment name. Use alphanumeric characters, hyphens, or underscores"
    echo "Usage: $0 [environment]"
    echo "  environment: Which instance to deploy to (prod|test|dev|staging|etc)"
    echo "Examples:"
    echo "  $0 prod"
    echo "  $0 test"
    echo "  $0 dev"
    exit 1
fi

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if instance info exists
if [ ! -f "${SCRIPT_DIR}/instance-info-${ENVIRONMENT}.env" ]; then
    echo "❌ No instance-info-${ENVIRONMENT}.env found."
    echo "   Create the ${ENVIRONMENT} instance first with: ./01-create-ec2-instance.sh ${ENVIRONMENT}"
    exit 1
fi

# Source instance info
source "${SCRIPT_DIR}/instance-info-${ENVIRONMENT}.env"

# Use Elastic IP if available, otherwise Public IP, otherwise Private IP
if [ -n "${ELASTIC_IP:-}" ] && [ "${ELASTIC_IP}" != "null" ]; then
    TARGET_IP=${ELASTIC_IP}
    ACCESS_TYPE="Elastic IP"
elif [ -n "${PUBLIC_IP:-}" ] && [ "${PUBLIC_IP}" != "null" ]; then
    TARGET_IP=${PUBLIC_IP}
    ACCESS_TYPE="Public IP"
else
    TARGET_IP=${PRIVATE_IP}
    ACCESS_TYPE="Private IP (requires VPN/network access)"
fi

echo "🚀 Deploying glossary app to EC2 instance..."
echo "Environment: ${ENVIRONMENT}"
echo "Target IP: ${TARGET_IP} (${ACCESS_TYPE})"
echo "Instance: ${INSTANCE_ID}"
echo ""

# Check if instance is running
echo "🔍 Checking instance status..."
INSTANCE_STATE=$(okta-aws khaas ec2 describe-instances \
    --region ${REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

if [ "${INSTANCE_STATE}" != "running" ]; then
    echo "❌ Instance is not running (state: ${INSTANCE_STATE})"
    echo "   Start the instance first with: aws ec2 start-instances --instance-ids ${INSTANCE_ID}"
    exit 1
fi

echo "✅ Instance is running"

# Wait for Docker installation to complete
echo "⏳ Waiting for Docker installation to complete..."
echo "   This may take 2-3 minutes on first run..."

# Function to check if Docker is ready
check_docker_ready() {
    ssh -i "${KEY_PATH}" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "docker --version" >/dev/null 2>&1
}

# Wait up to 5 minutes for Docker to be ready
for i in {1..30}; do
    if check_docker_ready; then
        echo "✅ Docker is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Timeout waiting for Docker installation"
        echo "   Try SSH manually: ssh -i \"${KEY_PATH}\" ec2-user@${TARGET_IP}"
        exit 1
    fi
    echo "   Waiting... (${i}/30)"
    sleep 10
done

# Deploy the application
echo "📦 Deploying ${ENVIRONMENT} environment..."

# Wait for Docker installation to complete
echo "⏳ Waiting for Docker installation to complete..."
echo "   This may take 2-3 minutes on first run..."
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "
while ! docker --version >/dev/null 2>&1; do
    echo 'Waiting for Docker...'
    sleep 10
done
echo 'Docker is ready!'
"

echo "✅ Docker is ready!"

echo "🐳 Deploying ${ENVIRONMENT} environment..."
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "
cd /home/ec2-user
./deploy.sh
" 2>&1 | sed 's/^/   /'

echo "🎉 ${ENVIRONMENT} deployment complete!"

# Verify deployment from outside
echo ""
echo "🔍 Verifying ${ENVIRONMENT} deployment from outside..."
sleep 5

# Always use port 80 since each environment has its own instance
TEST_PORT=80
HEALTH_ENDPOINT="http://${TARGET_IP}/health"
APP_ENDPOINT="http://${TARGET_IP}"

echo "Testing ${ENVIRONMENT} health endpoint on port ${TEST_PORT}..."
if ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "curl -s -f http://localhost:${TEST_PORT}/health" >/dev/null 2>&1; then
    echo "✅ ${ENVIRONMENT} health check successful!"
else
    echo "⏳ ${ENVIRONMENT} health check not ready yet, trying again in 10 seconds..."
    sleep 10
    if ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "curl -s -f http://localhost:${TEST_PORT}/health" >/dev/null 2>&1; then
        echo "✅ ${ENVIRONMENT} health check successful!"
    else
        echo "⚠️  ${ENVIRONMENT} health check failed, but app may still be starting..."
        echo "   Check manually via SSH: curl http://localhost/health"
    fi
fi

echo ""
echo "🎉 ${ENVIRONMENT} deployment completed!"
echo ""
echo "🌐 APPLICATION ACCESS (${ENVIRONMENT}):"
echo "   URL: ${APP_ENDPOINT}"
echo "   Health: ${HEALTH_ENDPOINT}"
echo ""
echo "🔧 MANAGEMENT:"
echo "   SSH: ssh -i \"${KEY_PATH}\" ec2-user@${TARGET_IP}"
echo "   ${ENVIRONMENT} Logs: ssh and run 'docker logs glossary-app'"
echo "   ${ENVIRONMENT} Restart: ssh and run 'docker restart glossary-app'"
echo ""
echo "💡 ENVIRONMENT COMMANDS (run via SSH):"
echo "   Deploy: ./deploy.sh"
echo "   Health Check: ./health-check.sh"
echo ""
echo "🔄 RE-RUN THIS SCRIPT:"
echo "📝 NEXT DEPLOYMENTS:"
echo "   Same deployment: ./03-deploy-app.sh ${ENVIRONMENT}"
