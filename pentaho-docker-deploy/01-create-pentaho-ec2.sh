#!/bin/bash
# 01-create-pentaho-ec2.sh
# Create EC2 instance and install Docker + prerequisites for Pentaho deployment

set -e

# Source shell configuration to get okta-aws function
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
elif [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# Configuration
ENVIRONMENT=${1:-"dev"}  # Default to dev, can specify test/prod

# Source configuration (input-only, never modified by scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/pentaho-deployment-${ENVIRONMENT}.env" ]; then
    echo "❌ Error: Configuration file not found: pentaho-deployment-${ENVIRONMENT}.env"
    echo "Available files:"
    ls -la "${SCRIPT_DIR}"/pentaho-deployment-*.env 2>/dev/null || echo "None found"
    exit 1
fi
source "${SCRIPT_DIR}/pentaho-deployment-${ENVIRONMENT}.env"

# Validate environment parameter provided
if [ -z "$ENVIRONMENT" ]; then
    echo "❌ Environment parameter required"
    echo "Usage: $0 [environment-name]"
    echo "Example: $0 dev"
    echo "Example: $0 test" 
    echo "Example: $0 monkey"
    exit 1
fi

echo "🚀 Creating Pentaho Docker deployment EC2 instance..."
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"
echo "Instance Type: ${INSTANCE_TYPE}"
echo ""

# Check AWS authentication status
echo "🔐 Checking AWS authentication..."
echo "Verifying Okta-AWS profile: ${AWS_PROFILE}"

# Test authentication with a quick, non-destructive command
if ! okta-aws ${AWS_PROFILE} sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ AWS authentication failed for profile: ${AWS_PROFILE}"
    echo ""
    echo "Please authenticate first:"
    echo "   okta-aws \${YOURPROFILE} sts get-caller-identity"
    echo ""
    echo "Or check that your Okta profile is correct in: pentaho-deployment-${ENVIRONMENT}.env"
    exit 1
fi

echo "✅ AWS authentication verified for profile: ${AWS_PROFILE}"
echo ""

# Check if key pair exists and key file is accessible
echo "🔑 Checking SSH key pair..."
if [ ! -f "${KEY_PATH}" ]; then
    echo "❌ Key file not found: ${KEY_PATH}"
    echo "Please ensure the key file exists and is accessible"
    exit 1
fi

# Verify key pair exists in AWS
okta-aws ${AWS_PROFILE} ec2 describe-key-pairs --region ${AWS_REGION} --key-names "${KEY_NAME}" >/dev/null 2>&1 || {
    echo "❌ Key pair '${KEY_NAME}' not found in AWS region ${AWS_REGION}"
    echo "Please ensure the key pair exists in AWS or update KEY_NAME in the script"
    exit 1
}

echo "✅ Using existing key pair: ${KEY_NAME}"
echo "✅ Key file found: ${KEY_PATH}"

# Use configured VPC and subnet from environment
echo "🔍 Using configured VPC for connectivity..."

echo "✅ Using VPC: ${VPC_ID}"
echo "✅ Using Subnet: ${SUBNET_ID}"

# Use all-open security group for full external access to Pentaho
echo "🛡️ Using all-open security group..."

echo "✅ Using all-open security group: ${SECURITY_GROUP_ID}"

# Security group rules not needed - all-open security group allows all traffic
echo "✅ All-open security group allows all necessary ports for Pentaho"
echo "   - SSH (22), HTTP (80), Pentaho (8080, 8081), DI Server (9001), etc."

# Create user data script for comprehensive setup (Ubuntu 22.04)
USER_DATA=$(cat << EOF
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

echo "Starting Pentaho Docker EC2 setup on Ubuntu..."

# Update system
apt-get update -y

# Setup additional EBS volume for Pentaho data
echo "Setting up additional EBS volume..."
# Wait for the additional EBS volume to be available
sleep 15
# Look specifically for nvme1n1 (the additional EBS volume)
if [ -b "/dev/nvme1n1" ]; then
    echo "Found additional volume: /dev/nvme1n1"
    # Format the volume
    mkfs.ext4 -F /dev/nvme1n1
    # Create mount point
    mkdir -p /mnt/pentaho-data
    # Mount the volume
    mount /dev/nvme1n1 /mnt/pentaho-data
    # Add to fstab for persistent mounting
    echo "/dev/nvme1n1 /mnt/pentaho-data ext4 defaults 0 2" >> /etc/fstab
    # Set ownership
    chown ${SSH_USER}:${SSH_USER} /mnt/pentaho-data
    echo "Additional EBS volume mounted at /mnt/pentaho-data"
    df -h /mnt/pentaho-data
else
    echo "No additional EBS volume found (/dev/nvme1n1), using root volume"
    df -h /
fi

# Install Docker
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Configure Docker to use EBS volume if available
if [ -d "/mnt/pentaho-data" ]; then
    echo "Configuring Docker to use EBS volume..."
    mkdir -p /etc/docker
    mkdir -p /mnt/pentaho-data/docker
    cat > /etc/docker/daemon.json << DOCKER_EOF
{
  "data-root": "/mnt/pentaho-data/docker"
}
DOCKER_EOF
    echo "Docker configured to use /mnt/pentaho-data/docker"
fi

systemctl start docker
systemctl enable docker
usermod -a -G docker ${SSH_USER}

# Restart Docker daemon to pick up EBS volume configuration
if [ -d "/mnt/pentaho-data" ]; then
    echo "Restarting Docker daemon to use EBS volume..."
    systemctl restart docker
    sleep 5
    # Verify Docker is using the correct data directory
    docker info 2>/dev/null | grep "Docker Root Dir" || echo "Docker info not available yet"
fi

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/2.21.0/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Java 11 (required for Pentaho)
apt-get install -y openjdk-11-jdk-headless
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> /home/${SSH_USER}/.bashrc

# Install unzip and wget
apt-get install -y unzip wget curl git

# Create pentaho directories on the additional volume if available
if [ -d "/mnt/pentaho-data" ]; then
    echo "Creating pentaho directories on additional EBS volume..."
    mkdir -p /mnt/pentaho-data/pentaho/{downloads,dockmaker,workspace,containers}
    chown -R ${SSH_USER}:${SSH_USER} /mnt/pentaho-data/pentaho
    # Create symlink from home directory
    ln -s /mnt/pentaho-data/pentaho /home/${SSH_USER}/pentaho
    chown -h ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/pentaho
else
    echo "Creating pentaho directories on root volume..."
    mkdir -p /home/${SSH_USER}/pentaho/{downloads,dockmaker,workspace,containers}
    chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/pentaho
fi

# Create environment template file
cat > /home/${SSH_USER}/pentaho/.env.template << 'ENV_EOF'
# Pentaho Docker Environment Configuration
PENTAHO_VERSION=10.2.0.0
ENVIRONMENT=dev
PENTAHO_SERVER_PORT=8080
CARTE_PORT=8081
DI_SERVER_PORT=9001

# Database Configuration (Optional)
DB_HOST=
DB_PORT=5432
DB_NAME=pentaho
DB_USER=pentaho
DB_PASSWORD=

# License Configuration
PENTAHO_LICENSE_PATH=/home/${SSH_USER}/pentaho/license

# Container Configuration
DOCKER_REGISTRY=
IMAGE_TAG=latest
MEMORY_LIMIT=4g
ENV_EOF

chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/pentaho/.env.template

# Create scripts directory
mkdir -p /home/${SSH_USER}/pentaho/scripts
chown ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/pentaho/scripts

echo "EC2 Pentaho Docker setup complete!" 
echo "Setup completed at: \$(date)" >> /var/log/pentaho-setup.log

# Log final disk usage and Docker configuration
echo "=== Final System Status ===" >> /var/log/pentaho-setup.log
df -h >> /var/log/pentaho-setup.log
echo "" >> /var/log/pentaho-setup.log
echo "Docker info:" >> /var/log/pentaho-setup.log
docker info 2>/dev/null | grep "Docker Root Dir" >> /var/log/pentaho-setup.log || echo "Docker not available during setup" >> /var/log/pentaho-setup.log
echo "========================" >> /var/log/pentaho-setup.log
EOF
)

# Create temporary user data file
TEMP_USER_DATA=$(mktemp)
echo "${USER_DATA}" > "${TEMP_USER_DATA}"

# Launch EC2 instance
echo "🖥️ Launching EC2 instance..."
INSTANCE_ID=$(okta-aws ${AWS_PROFILE} ec2 run-instances \
    --region ${AWS_REGION} \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --key-name "${KEY_NAME}" \
    --security-group-ids ${SECURITY_GROUP_ID} \
    --subnet-id ${SUBNET_ID} \
    --user-data file://${TEMP_USER_DATA} \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${EBS_VOLUME_SIZE},\"VolumeType\":\"${VOLUME_TYPE}\",\"DeleteOnTermination\":true}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-${ENVIRONMENT}},{Key=Project,Value=${PROJECT_NAME}},{Key=Environment,Value=${ENVIRONMENT}}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

# Clean up temporary file
rm "${TEMP_USER_DATA}"

echo "✅ Instance launched: ${INSTANCE_ID}"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
okta-aws ${AWS_PROFILE} ec2 wait instance-running --region ${AWS_REGION} --instance-ids ${INSTANCE_ID}

# Get instance details
INSTANCE_INFO=$(okta-aws ${AWS_PROFILE} ec2 describe-instances \
    --region ${AWS_REGION} \
    --instance-ids ${INSTANCE_ID} \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' \
    --output text)

# Parse IPs properly, handling "None" values and malformed output
RAW_PUBLIC_IP=$(echo ${INSTANCE_INFO} | awk '{print $1}')
RAW_PRIVATE_IP=$(echo ${INSTANCE_INFO} | awk '{print $2}')

# If we get something like "None 10.80.230.9", extract the IP properly
if [[ "$RAW_PUBLIC_IP" =~ ^None[[:space:]]+([0-9.]+)$ ]]; then
    # Extract IP from "None 10.80.230.9" format
    PUBLIC_IP=$(echo "$RAW_PUBLIC_IP" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/) print $i}')
elif [ "$RAW_PUBLIC_IP" = "None" ] || [ -z "$RAW_PUBLIC_IP" ]; then
    PUBLIC_IP=""
else
    PUBLIC_IP="$RAW_PUBLIC_IP"
fi

if [[ "$RAW_PRIVATE_IP" =~ ^None[[:space:]]+([0-9.]+)$ ]]; then
    # Extract IP from "None 10.80.230.9" format  
    PRIVATE_IP=$(echo "$RAW_PRIVATE_IP" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/) print $i}')
elif [ "$RAW_PRIVATE_IP" = "None" ] || [ -z "$RAW_PRIVATE_IP" ]; then
    PRIVATE_IP=""
else
    PRIVATE_IP="$RAW_PRIVATE_IP"
fi

# Save deployment runtime state (separate from input configuration)
cat > pentaho-deployment-${ENVIRONMENT}-runtime.state << EOF
# Pentaho Docker Deployment Runtime State - ${ENVIRONMENT}
# Generated: \$(date)
# This file contains dynamic state information from EC2 instance creation

INSTANCE_ID=${INSTANCE_ID}
PUBLIC_IP=${PUBLIC_IP}
PRIVATE_IP=${PRIVATE_IP}
INSTANCE_STATE=running
CREATED_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# SSH Connection (constructed from configuration)
# Use private IP if no public IP is available
if [ -n "${PUBLIC_IP}" ]; then
    SSH_IP="${PUBLIC_IP}"
else
    SSH_IP="${PRIVATE_IP}"
fi
SSH_COMMAND="ssh -i ${KEY_PATH} ${SSH_USER}@\${SSH_IP}"
EOF

echo ""
echo "🎉 Pentaho Docker EC2 instance created successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Instance ID: ${INSTANCE_ID}"
if [ -n "$PUBLIC_IP" ]; then
    echo "Public IP:   ${PUBLIC_IP}"
else
    echo "Public IP:   (none - private subnet)"
fi
echo "Private IP:  ${PRIVATE_IP}"
echo ""
echo "📋 Next Steps:"
echo "1. Wait ~3 minutes for user-data script to complete"
echo "2. Connect: ssh -i ${KEY_PATH} ${SSH_USER}@${SSH_IP}"
echo "3. Run: ./02-download-pentaho-files.sh ${ENVIRONMENT}"
echo "4. Run: ./03-build-pentaho-containers.sh ${ENVIRONMENT}"
echo "5. Run: ./04-deploy-pentaho.sh ${ENVIRONMENT}"
echo ""
echo "💾 Configuration: pentaho-deployment-${ENVIRONMENT}.env"
echo "💾 Runtime state: pentaho-deployment-${ENVIRONMENT}-runtime.state"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
