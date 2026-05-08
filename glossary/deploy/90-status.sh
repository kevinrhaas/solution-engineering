#!/bin/bash
# 90-status.sh
# Check status of all EC2 deployments

set -e

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shell configuration to get okta-aws function
if [ -f ~/.zshrc ]; then
    source ~/.zshrc
elif [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

echo "📊 EC2 Deployment Status"
echo "========================"
echo ""

# Function to check environment status
check_environment() {
    local env=$1
    local instance_file="${SCRIPT_DIR}/instance-info-${env}.env"
    
    if [ ! -f "${instance_file}" ]; then
        echo "❌ $(echo ${env} | tr '[:lower:]' '[:upper:]'): No instance configured"
        return
    fi

    # Source instance info
    source "${instance_file}"

    echo "🖥️  $(echo ${env} | tr '[:lower:]' '[:upper:]') ENVIRONMENT:"
    echo "   Instance ID: ${INSTANCE_ID}"
    echo "   Instance Type: ${INSTANCE_TYPE}"
    echo "   IP Address: ${PRIVATE_IP:-${PUBLIC_IP:-${ELASTIC_IP:-"N/A"}}}"
    
    # Check instance state
    INSTANCE_STATE=$(okta-aws khaas ec2 describe-instances \
        --region ${REGION} \
        --instance-ids ${INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text 2>/dev/null || echo "not-found")
    
    echo "   Instance State: ${INSTANCE_STATE}"
    
    if [ "$INSTANCE_STATE" = "running" ]; then
        echo "   🟢 Instance is running"
        
        # Determine target IP (prefer private, fallback to public/elastic)
        TARGET_IP=${PRIVATE_IP:-${PUBLIC_IP:-${ELASTIC_IP}}}
        
        # Check if we can SSH
        if ssh -i "${KEY_PATH}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "echo 'SSH OK'" 2>/dev/null | grep -q "SSH OK"; then
            echo "   🟢 SSH access: OK"
            
            # Check Docker containers
            echo "   📦 Docker containers:"
            ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null || echo "      ❌ Cannot check containers"
            
            # Check application health via SSH (more reliable for private networks)
            echo "   🏥 Application health:"
            
            # Check health (port 80) - all environments use port 80 now
            if ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ec2-user@${TARGET_IP} "curl -s -f http://localhost/health" >/dev/null 2>&1; then
                echo "      🟢 $(echo ${env} | tr '[:lower:]' '[:upper:]') (port 80): Healthy"
            else
                echo "      🔴 $(echo ${env} | tr '[:lower:]' '[:upper:]') (port 80): Not responding"
            fi
            
        else
            echo "   🔴 SSH access: Failed"
        fi
    elif [ "$INSTANCE_STATE" = "stopped" ]; then
        echo "   🟡 Instance is stopped"
    elif [ "$INSTANCE_STATE" = "not-found" ]; then
        echo "   🔴 Instance not found (may be terminated)"
    else
        echo "   🟡 Instance state: ${INSTANCE_STATE}"
    fi
    
    echo ""
}

# Check specific environment if provided, otherwise check all found environments
if [ $# -eq 1 ]; then
    # Check specific environment
    check_environment "$1"
else
    # Find all environment configs and check them
    found_envs=()
    for config_file in "${SCRIPT_DIR}"/instance-info-*.env; do
        if [ -f "$config_file" ]; then
            env_name=$(basename "$config_file" | sed 's/^instance-info-//' | sed 's/\.env$//')
            found_envs+=("$env_name")
        fi
    done
    
    if [ ${#found_envs[@]} -eq 0 ]; then
        echo "❌ No environment configurations found"
        echo "Create an environment with: ./01-create-ec2-instance.sh [environment]"
        echo ""
    else
        echo "Found environments: ${found_envs[*]}"
        echo ""
        for env in "${found_envs[@]}"; do
            check_environment "$env"
        done
    fi
fi

echo "🔗 QUICK ACCESS:"
echo ""

# Show access commands for running instances
found_configs=()
for config_file in "${SCRIPT_DIR}"/instance-info-*.env; do
    if [ -f "$config_file" ]; then
        env_name=$(basename "$config_file" | sed 's/^instance-info-//' | sed 's/\.env$//')
        found_configs+=("$env_name")
    fi
done

for env in "${found_configs[@]}"; do
    instance_file="${SCRIPT_DIR}/instance-info-${env}.env"
    if [ -f "${instance_file}" ]; then
        source "${instance_file}"
        
        INSTANCE_STATE=$(okta-aws khaas ec2 describe-instances \
            --region ${REGION} \
            --instance-ids ${INSTANCE_ID} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$INSTANCE_STATE" = "running" ]; then
            echo "📱 $(echo ${env} | tr '[:lower:]' '[:upper:]') Environment:"
            echo "   SSH: ssh -i \"${KEY_PATH}\" ec2-user@${PRIVATE_IP}"
            echo "   App: http://${PRIVATE_IP}"
            echo "   Deploy: ./deploy.sh ${env}"
            echo ""
        fi
    fi
done

echo "💡 MANAGEMENT:"
echo "   Create instance: ./01-create-ec2-instance.sh [environment]"
echo "   Transfer files: ./02-transfer-and-build.sh [environment]"
echo "   Deploy app: ./03-deploy-app.sh [environment]"
echo "   Full deploy: ./full-deploy.sh [environment]"
echo "   Quick deploy: ./deploy.sh [environment]"
echo "   Status: ./90-status.sh [environment]"
echo "   Cleanup: ./99-cleanup.sh [environment]"
