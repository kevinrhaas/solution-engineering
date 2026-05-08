#!/bin/bash

# 04-deploy-pentaho.sh
# Deploy Pentaho containers with proper resource configuration
# This script deploys the containers built by DockMaker

set -e

# Configuration
ENVIRONMENT=${1}

# Validate environment parameter
if [ -z "$ENVIRONMENT" ]; then
    echo "❌ Environment parameter required"
    echo "Usage: $0 [environment-name]"
    echo "Example: $0 dev"
    exit 1
fi

# Source configuration and runtime state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source input configuration (never modified by scripts)
if [ ! -f "${SCRIPT_DIR}/pentaho-deployment-${ENVIRONMENT}.env" ]; then
    echo "❌ Error: Configuration file not found: pentaho-deployment-${ENVIRONMENT}.env"
    echo "Available files:"
    ls -la "${SCRIPT_DIR}"/pentaho-deployment-*.env 2>/dev/null || echo "None found"
    exit 1
fi
source "${SCRIPT_DIR}/pentaho-deployment-${ENVIRONMENT}.env"

# Source runtime state (contains dynamic values from EC2 creation)
RUNTIME_STATE="${SCRIPT_DIR}/pentaho-deployment-${ENVIRONMENT}-runtime.state"
if [ ! -f "${RUNTIME_STATE}" ]; then
    echo "❌ Error: Runtime state file not found: ${RUNTIME_STATE}"
    echo "Please run Step 1 first to create the EC2 instance"
    exit 1
fi
source "${RUNTIME_STATE}"

echo "🚀 Starting Pentaho Container Deployment..."
echo "📍 EC2 Instance: ${INSTANCE_ID} (${PRIVATE_IP})"
echo "🔑 Using key: ${KEY_PATH}"

# Verify EC2 instance is accessible
echo "🔍 Verifying EC2 access..."
if ! ssh -i "${KEY_PATH}" -o ConnectTimeout=10 ${SSH_USER}@${PRIVATE_IP} 'echo "EC2 accessible"' > /dev/null 2>&1; then
    echo "❌ Cannot connect to EC2 instance at ${PRIVATE_IP}"
    echo "   Make sure the instance is running and your SSH key is correct"
    exit 1
fi

echo "✅ EC2 instance accessible"

# Execute the deployment process on EC2
echo "🚀 Starting container deployment on EC2..."

ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} << 'EOF'
    set -e
    
    echo "🔧 Setting up deployment environment..."
    
    # Verify docker-compose is available
    echo "🔍 Verifying docker-compose installation..."
    if ! command -v docker-compose >/dev/null 2>&1 || ! docker-compose --version >/dev/null 2>&1; then
        echo "❌ docker-compose not found or not working"
        echo "   Run 02-download-pentaho-files.sh first to install dependencies"
        exit 1
    fi
    echo "✅ docker-compose is ready"
    
    # Navigate to build directory
    cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles
    
    # Check if build artifacts exist
    if [[ ! -f "docker-compose.yml" ]]; then
        echo "❌ docker-compose.yml not found. Run 03-build-pentaho-containers.sh first"
        exit 1
    fi
    
    echo "✅ Build artifacts found"
    
    # Stop any existing containers
    echo "🛑 Stopping any existing containers..."
    if docker-compose ps --quiet > /dev/null 2>&1; then
        docker-compose down --remove-orphans || true
    fi
    
    # Fix resource limits for EC2 instance constraints
    echo "🔧 Adjusting resource limits for EC2 instance..."
    echo "   Target CPU limit: ${CONTAINER_CPU_LIMIT:-1.5}"
    echo "   Target Memory limit: ${CONTAINER_MEMORY_LIMIT:-3GB}"
    
    # Update CPU limits in docker-compose.yml - handle all possible patterns
    if grep -q "cpus:" docker-compose.yml; then
        echo "📝 Updating CPU limits to ${CONTAINER_CPU_LIMIT:-1.5}"
        # Create a backup and use a more reliable approach
        cp docker-compose.yml docker-compose.yml.backup
        
        # Use awk for more precise replacement to avoid sed escaping issues
        awk -v cpu="${CONTAINER_CPU_LIMIT:-1.5}" '
        /cpus:/ {
            # Replace the entire cpus line with the new value
            gsub(/cpus: *[^ ]*/, "cpus: " cpu)
        }
        { print }
        ' docker-compose.yml.backup > docker-compose.yml
        
        rm docker-compose.yml.backup
    fi
    
    # Update memory limits - handle various memory formats
    echo "📝 Updating memory limits to ${CONTAINER_MEMORY_LIMIT:-3GB}"
    # Convert to lowercase for consistency
    MEMORY_LIMIT=$(echo "${CONTAINER_MEMORY_LIMIT:-3GB}" | tr '[:upper:]' '[:lower:]')
    
    if grep -q "memory:" docker-compose.yml; then
        # Create backup and use awk for reliable replacement
        cp docker-compose.yml docker-compose.yml.backup
        
        awk -v mem="$MEMORY_LIMIT" '
        /memory:/ {
            # Replace the entire memory line with the new value
            gsub(/memory: *[^ ]*/, "memory: " mem)
        }
        { print }
        ' docker-compose.yml.backup > docker-compose.yml
        
        rm docker-compose.yml.backup
    fi
    
    echo "📊 Current docker-compose.yml resource configuration:"
    grep -A2 -B2 "cpus:\|memory:" docker-compose.yml || echo "No explicit resource limits found"
    
    # Validate CPU limits don't exceed instance capacity
    echo "🔍 Validating resource limits against instance capacity..."
    CPU_COUNT=$(nproc)
    echo "   Available CPUs: $CPU_COUNT"
    
    # Check if any CPU limit in docker-compose.yml exceeds available CPUs
    if grep -q "cpus:" docker-compose.yml; then
        # Extract CPU value from various formats (with or without quotes)
        CONFIGURED_CPU=$(grep "cpus:" docker-compose.yml | head -1 | sed 's/.*cpus: *["\x27]*\([0-9]*\.*[0-9]*\).*/\1/')
        
        # Validate we got a numeric value
        if [[ "$CONFIGURED_CPU" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            echo "   Configured CPU limit: $CONFIGURED_CPU"
            # Convert to integer comparison (multiply by 10 to handle decimals)
            CONFIGURED_CPU_INT=$(echo "$CONFIGURED_CPU * 10" | awk '{printf "%.0f", $1}')
            CPU_COUNT_INT=$(echo "$CPU_COUNT * 10" | awk '{printf "%.0f", $1}')
            
            if [ "$CONFIGURED_CPU_INT" -gt "$CPU_COUNT_INT" ]; then
                echo "⚠️  WARNING: Configured CPU limit ($CONFIGURED_CPU) exceeds available CPUs ($CPU_COUNT)"
                echo "🔧 Fixing CPU limit to safe value..."
                SAFE_CPU_LIMIT="1.5"  # Safe default for t3.large (2 vCPU)
                if [ "$CPU_COUNT" -eq "1" ]; then
                    SAFE_CPU_LIMIT="0.8"  # For single CPU instances
                fi
                # Apply the same comprehensive patterns as above
                sed -i "s/cpus: '[0-9]*\.[0-9]*'/cpus: '$SAFE_CPU_LIMIT'/g" docker-compose.yml
                sed -i "s/cpus: '[0-9]*'/cpus: '$SAFE_CPU_LIMIT'/g" docker-compose.yml
                sed -i 's/cpus: "[0-9]*\.[0-9]*"/cpus: "'$SAFE_CPU_LIMIT'"/g' docker-compose.yml
                sed -i 's/cpus: "[0-9]*"/cpus: "'$SAFE_CPU_LIMIT'"/g' docker-compose.yml
                sed -i "s/cpus: [0-9]*\.[0-9]*/cpus: $SAFE_CPU_LIMIT/g" docker-compose.yml
                sed -i "s/cpus: [0-9]*/cpus: $SAFE_CPU_LIMIT/g" docker-compose.yml
                echo "   Updated CPU limit to: $SAFE_CPU_LIMIT"
            else
                echo "✅ CPU limit ($CONFIGURED_CPU) is within available capacity"
            fi
        else
            echo "⚠️  Could not parse CPU limit value: '$CONFIGURED_CPU'"
        fi
    fi
    
    # Start the containers
    echo "🐳 Starting Pentaho containers..."
    docker-compose up -d
    
    # Wait for containers to be ready
    echo "⏳ Waiting for containers to start..."
    sleep 10
    
    # Check container status
    echo "📊 Container status:"
    docker-compose ps
    
    # Verify containers are running
    if docker-compose ps --quiet | wc -l | grep -q "2"; then
        echo "✅ Both containers are running"
    else
        echo "⚠️  Not all containers are running"
        docker-compose logs --tail=20
    fi
    
    # Check if Pentaho server is responding
    echo "🔍 Testing Pentaho server connectivity..."
    sleep 30  # Give server time to fully start
    
    # Test local connectivity
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:80/pentaho/Login | grep -q "200\|302"; then
        echo "✅ Pentaho server is responding locally"
    else
        echo "⚠️  Pentaho server not responding locally yet (may still be starting)"
    fi
    
    # Fix explicit port binding for external access
    echo "🔧 Ensuring explicit port binding for external access..."
    if grep -q '"\${PORT}:8080"' docker-compose.yml; then
        echo "📝 Updating port binding to be explicit (0.0.0.0:\${PORT}:8080)"
        sed -i 's/"\${PORT}:8080"/"0.0.0.0:\${PORT}:8080"/' docker-compose.yml
        
        echo "🔄 Restarting containers with updated port binding..."
        docker-compose down > /dev/null 2>&1
        sleep 3
        docker-compose up -d > /dev/null 2>&1
        sleep 30
    fi
    
    echo "🎉 Deployment completed!"
    echo ""
    
    # Get instance networking info
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "No public IP")
    
    echo "📍 Access Information:"
    echo "   Local (from EC2): http://localhost:80/pentaho"
    echo "   Private IP: http://${PRIVATE_IP}:80/pentaho"
    if [[ "$PUBLIC_IP" != "No public IP" ]]; then
        echo "   Public IP: http://${PUBLIC_IP}:80/pentaho"
    fi
    echo ""
    echo "🔐 Login Credentials:"
    echo "   Username: admin"
    echo "   Password: password"
    echo ""
    
    # Test external connectivity
    echo "� Testing external connectivity..."
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://${PRIVATE_IP}:80/pentaho/Login | grep -q "200\|302"; then
        echo "✅ External access working via private IP!"
    else
        echo "⚠️  External access not working - use SSH tunnel:"
        echo "   ssh -L 80:localhost:80 -i ~/.ssh/pentaho+_se_keypair.pem ${SSH_USER}@${PRIVATE_IP}"
        echo "   Then access: http://localhost:80/pentaho"
    fi
    echo ""
    
EOF

echo "✅ Pentaho container deployment completed!"
echo ""
echo "🎯 Next Steps:"
echo "1. Direct access: http://${PRIVATE_IP}:80/pentaho"
echo "2. SSH tunnel (alternative): ssh -L 80:localhost:80 -i ${KEY_PATH} ${SSH_USER}@${PRIVATE_IP}"
echo "3. Login with: admin/password"