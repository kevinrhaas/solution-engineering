#!/bin/bash
# 01-create-ec2-instance.sh
# Simple EC2 + Docker deployment for glossary app

set -e

# Source shell configuration to get okta-aws function
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
elif [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# Configuration
ENVIRONMENT=${1:-"prod"}  # Default to prod, can specify test
AWS_REGION="us-west-2"
INSTANCE_TYPE="t3.small"  # 2GB RAM to handle security agents
AMI_ID="ami-08d8ac128e0a1b91c"  # Amazon Linux 2023 (us-west-2)
KEY_NAME="pentaho+_se_keypair"  # Use existing key
KEY_PATH="$HOME/.ssh/pentaho+_se_keypair.pem"
PROJECT_NAME="glossary"

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

echo "🚀 Creating simple EC2 + Docker deployment..."
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo ""

# Check if key pair exists and key file is accessible
echo "🔑 Checking SSH key pair..."
if [ ! -f "${KEY_PATH}" ]; then
    echo "❌ Key file not found: ${KEY_PATH}"
    echo "Please ensure the key file exists and is accessible"
    exit 1
fi

# Verify key pair exists in AWS
okta-aws khaas ec2 describe-key-pairs --region ${AWS_REGION} --key-names ${KEY_NAME} >/dev/null 2>&1 || {
    echo "❌ Key pair '${KEY_NAME}' not found in AWS region ${AWS_REGION}"
    echo "Please ensure the key pair exists in AWS or update KEY_NAME in the script"
    exit 1
}

echo "✅ Using existing key pair: ${KEY_NAME}"
echo "✅ Key file found: ${KEY_PATH}"

# Use the same VPC as RDS database (where PDC servers are)
echo "🔍 Using RDS VPC for database connectivity..."
VPC_ID="vpc-095f761a169c10b8e"  # Same VPC as airlinesample RDS and PDC servers
SUBNET_ID="subnet-059321ee33ee549e7"  # Same subnet as PDC servers

echo "✅ Using VPC: ${VPC_ID}"
echo "✅ Using Subnet: ${SUBNET_ID}"

# Use the all-open security group for better connectivity
echo "🛡️ Using all-open security group for full connectivity..."
SECURITY_GROUP_ID="sg-020200447994fa148"  # All-open security group

echo "✅ Using existing security group: ${SECURITY_GROUP_ID}"
# Create user data script for Docker installation
USER_DATA=$(cat << EOF
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Create deployment directory
mkdir -p /home/ec2-user/app
chown ec2-user:ec2-user /home/ec2-user/app

# Set environment variable
echo "export GLOSSARY_ENV=${ENVIRONMENT}" >> /home/ec2-user/.bashrc

# Create simple deployment script
cat > /home/ec2-user/deploy.sh << 'DEPLOY_EOF'
#!/bin/bash
# Simple deployment script
set -e

# Environment is fixed for this instance
DEPLOY_ENV="${ENVIRONMENT}"
CONTAINER_NAME="glossary-app"
HOST_PORT=80
IMAGE_TAG="glossary-local:latest"

echo "🚀 Deploying ${ENVIRONMENT} environment on port ${HOST_PORT}..."

# Stop and remove existing container
docker stop \$CONTAINER_NAME 2>/dev/null || true
docker rm \$CONTAINER_NAME 2>/dev/null || true

# Check if app directory exists and has Dockerfile
if [ ! -f "/home/ec2-user/app/Dockerfile" ]; then
    echo "❌ Dockerfile not found in /home/ec2-user/app/"
    echo "Please run the deployment script from your local machine first"
    exit 1
fi

# Build image locally
echo "🔨 Building Docker image: \$IMAGE_TAG"
cd /home/ec2-user/app
docker build --platform linux/amd64 -t \$IMAGE_TAG .

# Run the container
echo "🚀 Starting container: \$CONTAINER_NAME"
docker run -d \\
    --name \$CONTAINER_NAME \\
    --restart unless-stopped \\
    -p \$HOST_PORT:5000 \\
    --env-file /home/ec2-user/app/.env \\
    -e ENVIRONMENT=\$DEPLOY_ENV \\
    \$IMAGE_TAG

echo "✅ ${ENVIRONMENT} environment deployed and running on port \$HOST_PORT"
DEPLOY_EOF

chmod +x /home/ec2-user/deploy.sh
chown ec2-user:ec2-user /home/ec2-user/deploy.sh

# Create health check script
cat > /home/ec2-user/health-check.sh << 'HEALTH_EOF'
#!/bin/bash
echo "Checking ${ENVIRONMENT} environment on port 80..."
curl -f http://localhost:80/health || echo "Health check failed for ${ENVIRONMENT} environment"
HEALTH_EOF

chmod +x /home/ec2-user/health-check.sh
chown ec2-user:ec2-user /home/ec2-user/health-check.sh

echo "EC2 instance setup complete!" > /var/log/user-data.log
EOF
)

# Create temporary user data file
TEMP_USER_DATA=$(mktemp)
echo "${USER_DATA}" > "${TEMP_USER_DATA}"

# Launch EC2 instance
echo "🖥️ Launching EC2 instance..."
INSTANCE_ID=$(okta-aws khaas ec2 run-instances \
    --region ${AWS_REGION} \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --key-name ${KEY_NAME} \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --subnet-id ${SUBNET_ID} \
    --user-data file://"${TEMP_USER_DATA}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-server-${ENVIRONMENT}},{Key=Project,Value=${PROJECT_NAME}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

# Clean up temporary file
rm "${TEMP_USER_DATA}"

echo "✅ Instance created: ${INSTANCE_ID}"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
okta-aws khaas ec2 wait instance-running --region ${AWS_REGION} --instance-ids ${INSTANCE_ID}

# Get instance details
INSTANCE_INFO=$(okta-aws khaas ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,PrivateIp:PrivateIpAddress,State:State.Name}' \
    --output json)

PUBLIC_IP=$(echo ${INSTANCE_INFO} | jq -r '.PublicIp')
PRIVATE_IP=$(echo ${INSTANCE_INFO} | jq -r '.PrivateIp')

echo "✅ Instance is running!"
echo "   Instance ID: ${INSTANCE_ID}"
echo "   Public IP: ${PUBLIC_IP:-'None (private VPC)'}"
echo "   Private IP: ${PRIVATE_IP}"
echo ""
echo "⚠️  NOTE: This instance is in a private VPC (same as RDS database)"
echo "    Direct SSH access requires VPN or bastion host"

# Save configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > "${SCRIPT_DIR}/instance-info-${ENVIRONMENT}.env" << INFO_EOF
# EC2 Instance Information - ${ENVIRONMENT}
ENVIRONMENT=${ENVIRONMENT}
REGION=${AWS_REGION}
INSTANCE_ID=${INSTANCE_ID}
INSTANCE_TYPE=${INSTANCE_TYPE}
PUBLIC_IP=${PUBLIC_IP}
PRIVATE_IP=${PRIVATE_IP}
VPC_ID=${VPC_ID}
SUBNET_ID=${SUBNET_ID}
SECURITY_GROUP_ID=${SECURITY_GROUP_ID}
KEY_NAME=${KEY_NAME}
KEY_PATH="$HOME/.ssh/pentaho+_se_keypair.pem"

# Access Information
SSH_COMMAND="ssh -i \"${KEY_PATH}\" ec2-user@${PRIVATE_IP}"
APP_URL="http://${PRIVATE_IP}"
HEALTH_URL="http://${PRIVATE_IP}/health"
INFO_EOF

echo ""
echo "🎉 EC2 instance created successfully!"
echo ""
echo "📝 NEXT STEPS:"
echo "   NOTE: Instance uses all-open security group for direct access"
echo "   1. Direct access available with all-open security group"
echo "   2. SSH and HTTP access should work directly"
echo "   3. Deploy app directly via HTTP"
echo ""
echo "📋 DEPLOYMENT OPTIONS:"
echo "   Option A: SSH via PDC server as bastion:"
echo "     1. SSH to PDC server: ssh -i \"${KEY_PATH}\" ec2-user@<PDC_PUBLIC_IP>"
echo "     2. From PDC, SSH to app server: ssh ec2-user@${PRIVATE_IP}"
echo "   Option B: Use existing network connectivity (VPN/direct)"
echo ""
echo "🔗 ACCESS:"
echo "   SSH: ssh -i \"${KEY_PATH}\" ec2-user@${PRIVATE_IP} (direct SSH access available)"
echo "   $(echo ${ENVIRONMENT} | tr '[:lower:]' '[:upper:]') App: http://${PRIVATE_IP} (direct HTTP access available)"
echo ""
echo "💻 ENVIRONMENT SUPPORT:"
echo "   Deploy: ssh to instance, run './deploy.sh'"
echo "   Health Check: ssh to instance, run './health-check.sh'"
echo ""
echo "💾 Configuration saved to: instance-info-${ENVIRONMENT}.env"
