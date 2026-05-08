#!/bin/bash
# 99-destroy.sh
# Destroy EC2 resources when no longer needed

set -e

# Source shell configuration to get okta-aws function
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
elif [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# Configuration
ENVIRONMENT=${1:-""}  # Can specify any environment name, or leave empty to see options

if [ -z "$ENVIRONMENT" ]; then
    echo "🔥 EC2 Destroy Utility"
    echo ""
    echo "Available instances:"
    
    # Determine script directory to find instance files
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    for env_file in "${SCRIPT_DIR}"/instance-info-*.env; do
        if [ -f "$env_file" ]; then
            ENV_NAME=$(basename "$env_file" | sed 's/instance-info-//; s/.env//')
            source "$env_file"
            IP_ADDRESS=${PRIVATE_IP:-${PUBLIC_IP:-${ELASTIC_IP:-"No IP"}}}
            echo "  ${ENV_NAME}: ${INSTANCE_ID} (${IP_ADDRESS})"
        fi
    done
    echo ""
    echo "Usage: $0 [environment|all]"
    echo "Examples:"
    echo "  $0 test      # Destroy test environment"
    echo "  $0 prod      # Destroy production environment"
    echo "  $0 dev       # Destroy development environment"
    echo "  $0 staging   # Destroy staging environment"
    echo "  $0 all       # Destroy all environments"
    exit 0
fi

# Function to destroy environment
destroy_environment() {
    local env=$1
    
    # Determine script directory to find instance files
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [ ! -f "${SCRIPT_DIR}/instance-info-${env}.env" ]; then
        echo "❌ No instance-info-${env}.env found. Nothing to destroy for ${env}."
        return
    fi

    # Source instance info
    source "${SCRIPT_DIR}/instance-info-${env}.env"

    echo "🔥 Destroying ${env} environment..."
    echo "Instance: ${INSTANCE_ID}"
    echo "IP Address: ${PRIVATE_IP:-${PUBLIC_IP:-${ELASTIC_IP:-'None'}}}"
    echo ""

    # Terminate EC2 instance
    echo "🔥 Terminating EC2 instance..."
    okta-aws khaas ec2 terminate-instances \
        --region ${REGION} \
        --instance-ids ${INSTANCE_ID}

    echo "✅ Instance termination initiated"

    # Wait for instance termination (optional)
    echo "⏳ Waiting for instance to terminate..."
    okta-aws khaas ec2 wait instance-terminated --region ${REGION} --instance-ids ${INSTANCE_ID}
    echo "✅ Instance terminated"

    # NOTE: Security group is shared with PDC servers - DO NOT DELETE
    echo "🛡️ Security group is shared resource - keeping ${SECURITY_GROUP_ID}"

    # Clean up local files
    echo "📁 Cleaning up local configuration..."
    rm -f "${SCRIPT_DIR}/instance-info-${env}.env"

    echo ""
    echo "🎉 ${env} environment destruction completed!"
    echo ""
    echo "🗑️  RESOURCES DELETED:"
    echo "   ✅ EC2 Instance: ${INSTANCE_ID}"
    echo "   ⚠️  Security Group: ${SECURITY_GROUP_ID} (kept - shared resource)"
    echo "   ✅ Local config file"
}

# Validate environment
if [ "$ENVIRONMENT" = "all" ]; then
    echo "⚠️  This will PERMANENTLY DELETE ALL EC2 instances."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    # Determine script directory to find instance files
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Clean up all environments found
    for env_file in "${SCRIPT_DIR}"/instance-info-*.env; do
        if [ -f "$env_file" ]; then
            ENV_NAME=$(basename "$env_file" | sed 's/instance-info-//; s/.env//')
            destroy_environment "$ENV_NAME" 2>/dev/null || echo "Failed to destroy $ENV_NAME environment"
        fi
    done
else
    # Validate environment name format
    if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "❌ Invalid environment name. Use alphanumeric characters, hyphens, or underscores"
        echo "Usage: $0 [environment|all]"
        echo "Examples: prod, test, dev, staging, my-feature, v2-test"
        exit 1
    fi
    
    echo "⚠️  This will PERMANENTLY DELETE the ${ENVIRONMENT} EC2 instance."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    destroy_environment "$ENVIRONMENT"
fi
