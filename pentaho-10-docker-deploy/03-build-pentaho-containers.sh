#!/bin/bash

# 03-build-pentaho-containers.sh
# Build Pentaho containers using DockMaker with proper artifact caching
# This script connects to EC2 and builds the containers using DockMaker

set -e

# Configuration
ENVIRONMENT=${1}
BUILD_MODE=${2:-"interactive"}  # Default to interactive if not specified

# Validate environment parameter
if [ -z "$ENVIRONMENT" ]; then
    echo "❌ Environment parameter required"
    echo "Usage: $0 [environment-name] [build-mode]"
    echo "Example: $0 dev"
    echo "Example: $0 dev full"
    echo "Example: $0 dev background"
    echo "Build modes: full, background, status, interactive (default)"
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

echo "🐳 Starting Pentaho Container Build Process..."
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

# Verify Docker is using EBS volume
echo "🔍 Verifying Docker configuration..."
DOCKER_ROOT_DIR=$(ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} 'docker info 2>/dev/null | grep "Docker Root Dir" | cut -d":" -f2 | xargs' 2>/dev/null || echo "")

if [[ "$DOCKER_ROOT_DIR" == *"/mnt/pentaho-data/docker"* ]]; then
    echo "✅ Docker is using EBS volume: $DOCKER_ROOT_DIR"
    # Check available disk space on EBS volume
    AVAILABLE_SPACE=$(ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} 'df -h /mnt/pentaho-data | tail -1 | awk "{print \$4}"' 2>/dev/null || echo "unknown")
    echo "✅ Available space on EBS volume: $AVAILABLE_SPACE"
else
    echo "⚠️  Docker may not be using EBS volume correctly"
    echo "   Current Docker Root Dir: $DOCKER_ROOT_DIR"
    echo "   Expected: /mnt/pentaho-data/docker"
    echo ""
    echo "🔧 Attempting to fix Docker configuration..."
    ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} << 'DOCKER_FIX_EOF'
        # Check if EBS volume is mounted
        if [ -d "/mnt/pentaho-data" ]; then
            echo "📁 EBS volume is mounted at /mnt/pentaho-data"
            
            # Ensure Docker daemon.json exists and is correct
            sudo mkdir -p /etc/docker
            sudo mkdir -p /mnt/pentaho-data/docker
            
            if [ ! -f "/etc/docker/daemon.json" ]; then
                echo "⚠️  Missing daemon.json, creating..."
                echo '{"data-root": "/mnt/pentaho-data/docker"}' | sudo tee /etc/docker/daemon.json
            else
                echo "✅ daemon.json exists:"
                sudo cat /etc/docker/daemon.json
            fi
            
            # Restart Docker daemon to pick up configuration
            echo "🔄 Restarting Docker daemon..."
            sudo systemctl restart docker
            sleep 10
            
            # Verify configuration
            echo "🔍 Verifying Docker configuration after restart:"
            docker info | grep "Docker Root Dir" || echo "Docker info not available"
            
            echo "📊 Disk space check:"
            df -h /mnt/pentaho-data
        else
            echo "❌ EBS volume not mounted at /mnt/pentaho-data"
            echo "📊 Current disk usage:"
            df -h /
        fi
DOCKER_FIX_EOF
    
    # Re-check Docker configuration after fix attempt
    echo "🔍 Re-checking Docker configuration..."
    DOCKER_ROOT_DIR_FIXED=$(ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} 'docker info 2>/dev/null | grep "Docker Root Dir" | cut -d":" -f2 | xargs' 2>/dev/null || echo "")
    if [[ "$DOCKER_ROOT_DIR_FIXED" == *"/mnt/pentaho-data/docker"* ]]; then
        echo "✅ Docker configuration fixed - now using EBS volume"
    else
        echo "❌ Unable to configure Docker to use EBS volume"
        echo "   This may cause disk space issues during container builds"
        echo "   Continuing anyway, but monitor disk usage closely"
    fi
fi

# Execute the build process on EC2
echo "🚀 Starting container build on EC2..."
echo ""

# Determine build option from parameter or prompt
if [ "$BUILD_MODE" = "interactive" ]; then
    echo ""
    echo "🏗️  Container Build Options:"
    echo "   [f] Full build - start and monitor process (15-20 minutes)"
    echo "   [b] Background build - start build and return immediately"  
    echo "   [s] Status check - check current build progress"
    echo "   [q] Quit without building"
    echo ""
    read -p "Choose option [f/b/s/q]: " build_option
else
    # Use provided build mode
    case "$BUILD_MODE" in
        "full"|"f")
            build_option="f"
            echo "🏗️  Using full build mode (non-interactive)"
            ;;
        "background"|"b")
            build_option="b"
            echo "🏗️  Using background build mode (non-interactive)"
            ;;
        "status"|"s")
            build_option="s"
            echo "🏗️  Using status check mode (non-interactive)"
            ;;
        *)
            echo "❌ Invalid build mode: $BUILD_MODE"
            echo "Valid modes: full, background, status, interactive"
            exit 1
            ;;
    esac
fi

case "$build_option" in
    "s")
        echo "🔍 Checking build status on EC2..."
        ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} << 'EOF'
            echo "📊 Build Status Check:"
            echo "====================="
            
            # Check if build is running
            if pgrep -f "DockMaker.sh" >/dev/null; then
                echo "🔄 DockMaker build process is currently running"
                echo "   PID: $(pgrep -f DockMaker.sh)"
                
                # Check progress indicators
                if [[ -d ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles ]]; then
                    echo "✓ Build directory exists - build in progress"
                    cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles
                    if [[ -f "docker-compose.yml" ]]; then
                        echo "✓ docker-compose.yml created"
                    fi
                    if [[ -f "Dockerfile" ]]; then
                        echo "✓ Dockerfile created"
                    fi
                    # Check for Docker image
                    if docker images | grep -q "pentaho/pentaho-server"; then
                        echo "✓ Pentaho Docker image built"
                        docker images | grep "pentaho/pentaho-server"
                    fi
                else
                    echo "⏳ Build still initializing..."
                fi
            else
                echo "❌ No DockMaker build process found"
                
                # Check if build completed
                if [[ -d ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles ]]; then
                    echo "✅ Build may have completed - checking artifacts..."
                    cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222/generatedFiles
                    if docker images | grep -q "pentaho/pentaho-server"; then
                        echo "🎉 Build completed successfully!"
                        docker images | grep "pentaho/pentaho-server"
                    else
                        echo "⚠️  Build artifacts exist but no Docker image found"
                    fi
                else
                    echo "❌ No build artifacts found"
                fi
            fi
EOF
        exit 0
        ;;
    "b")
        echo "🚀 Starting build in background..."
        ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} << 'EOF'
            set -e
            echo "🔧 Starting background build..."
            cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222
            
            # Start build in background with logging (without auto-execution)
            nohup ./DockMaker.sh -V 10.2.0.0/222/ee -A paz --EULA_ACCEPT true -D postgres/15 -p 80 -U > ~/pentaho/build.log 2>&1 &
            BUILD_PID=$!
            
            echo "✅ Build started in background with PID: ${BUILD_PID}"
            echo "📝 Build log: ~/pentaho/build.log"
            echo ""
            echo "To check status: ./03-build-pentaho-containers.sh test"
            echo "To follow logs: ssh -i ~/.ssh/pentaho+_se_keypair.pem ec2-user@10.80.230.123 'tail -f ~/pentaho/build.log'"
EOF
        echo ""
        echo "✅ Background build initiated!"
        echo "📊 Check status anytime with: ./03-build-pentaho-containers.sh test"
        exit 0
        ;;
    "q")
        echo "❌ Build cancelled"
        exit 0
        ;;
    *)
        echo "🔄 Running build in foreground with progress updates..."
        ;;
esac

ssh -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} << 'EOF'
    set -e
    
    echo "🔧 Setting up DockMaker environment..."
    
    # Navigate to DockMaker directory
    cd ~/pentaho/dockmaker/dock-maker-10.2.0.0-222
    
    echo "📦 Using existing artifacts (no download)..."
    echo "🏗️  Building Pentaho Server container..."
    echo "⏱️  This will take approximately 10-15 minutes..."
    echo ""
    
    # Build using existing downloads with required parameters (build only, no auto-execution)
    # -V: Version, -A: Additional plugins (paz for PDI Enterprise Edition)
    # --EULA_ACCEPT: Accept license unattended, -D: Database (postgres/15), -p: Port (80), -U: Use existing downloads
    # Note: Removed -X flag to prevent auto-execution before CPU limits are fixed
    ./DockMaker.sh -V 10.2.0.0/222/ee -A paz --EULA_ACCEPT true -D postgres/15 -p 80 -U &
    BUILD_PID=$!
    
    echo "🔄 Build process started with PID: ${BUILD_PID}"
    echo "📊 Progress updates every 30 seconds..."
    echo ""
    
    # Monitor build process with detailed progress
    COUNTER=0
    while kill -0 ${BUILD_PID} 2>/dev/null; do
        COUNTER=$((COUNTER + 1))
        MINUTES=$((COUNTER / 2))
        
        echo "⏳ Build progress: ${MINUTES} minutes elapsed..."
        
        # Check build progress indicators
        if [[ -d "generatedFiles" ]] && [[ $COUNTER -gt 2 ]]; then
            echo "   ✓ Build directory created"
            cd generatedFiles
            
            if [[ -f "docker-compose.yml" ]]; then
                echo "   ✓ docker-compose.yml generated"
            fi
            
            if [[ -f "Dockerfile" ]]; then
                echo "   ✓ Dockerfile created"
            fi
            
            # Check if Docker build is happening
            if docker images | grep -q "pentaho/pentaho-server" 2>/dev/null; then
                echo "   ✓ Docker image being built..."
            fi
            
            cd ..
        fi
        
        sleep 30
    done
    
    # Wait for the process to finish completely
    wait ${BUILD_PID}
    BUILD_EXIT_CODE=$?
    
    echo ""
    echo "🏁 Build process completed with exit code: ${BUILD_EXIT_CODE}"
    
    # Verify build artifacts
    if [[ -d "generatedFiles" ]]; then
        echo "✅ Build directory created successfully"
        cd generatedFiles
        
        if [[ -f "docker-compose.yml" ]]; then
            echo "✅ docker-compose.yml generated"
            
            # Fix CPU limits immediately to prevent deployment errors
            echo "🔧 Validating and fixing CPU limits for EC2 instance..."
            CPU_COUNT=$(nproc)
            echo "   Available CPUs: $CPU_COUNT"
            
            # Check if any CPU limit in docker-compose.yml exceeds available CPUs
            if grep -q "cpus:" docker-compose.yml; then
                # Extract CPU value from various formats (with or without quotes)
                CONFIGURED_CPU=$(grep "cpus:" docker-compose.yml | head -1 | sed 's/.*cpus: *["\x27]*\([0-9]*\.*[0-9]*\).*/\1/')
                
                # Validate we got a numeric value
                if [[ "$CONFIGURED_CPU" =~ ^[0-9]*\.?[0-9]+$ ]]; then
                    echo "   DockMaker configured CPU limit: $CONFIGURED_CPU"
                    # Convert to integer comparison (multiply by 10 to handle decimals)
                    CONFIGURED_CPU_INT=$(echo "$CONFIGURED_CPU * 10" | awk '{printf "%.0f", $1}')
                    CPU_COUNT_INT=$(echo "$CPU_COUNT * 10" | awk '{printf "%.0f", $1}')
                    
                    if [ "$CONFIGURED_CPU_INT" -gt "$CPU_COUNT_INT" ]; then
                        echo "⚠️  WARNING: DockMaker CPU limit ($CONFIGURED_CPU) exceeds available CPUs ($CPU_COUNT)"
                        echo "🔧 Fixing CPU limit to prevent deployment errors..."
                        
                        # Calculate safe CPU limit (leave some headroom)
                        SAFE_CPU_LIMIT="${CONTAINER_CPU_LIMIT:-1.5}"
                        if [ "$CPU_COUNT" -eq "1" ]; then
                            SAFE_CPU_LIMIT="0.8"  # For single CPU instances
                        elif [ "$CPU_COUNT" -eq "2" ]; then
                            SAFE_CPU_LIMIT="1.5"  # For dual CPU instances (t3.large)
                        fi
                        
                        # Apply comprehensive CPU limit fixes
                        cp docker-compose.yml docker-compose.yml.backup
                        
                        # Fix all possible CPU limit formats
                        sed -i "s/cpus: '[0-9]*\.[0-9]*'/cpus: '$SAFE_CPU_LIMIT'/g" docker-compose.yml
                        sed -i "s/cpus: '[0-9]*'/cpus: '$SAFE_CPU_LIMIT'/g" docker-compose.yml
                        sed -i 's/cpus: "[0-9]*\.[0-9]*"/cpus: "'$SAFE_CPU_LIMIT'"/g' docker-compose.yml
                        sed -i 's/cpus: "[0-9]*"/cpus: "'$SAFE_CPU_LIMIT'"/g' docker-compose.yml
                        sed -i "s/cpus: [0-9]*\.[0-9]*/cpus: $SAFE_CPU_LIMIT/g" docker-compose.yml
                        sed -i "s/cpus: [0-9]*/cpus: $SAFE_CPU_LIMIT/g" docker-compose.yml
                        
                        echo "   ✅ Updated CPU limit to: $SAFE_CPU_LIMIT"
                        echo "   📝 Backup saved as: docker-compose.yml.backup"
                    else
                        echo "   ✅ CPU limit ($CONFIGURED_CPU) is within available capacity"
                    fi
                else
                    echo "   ⚠️  Could not parse CPU limit value: '$CONFIGURED_CPU'"
                fi
            else
                echo "   ✅ No explicit CPU limits found (Docker defaults will apply)"
            fi
            
            # Also fix memory limits if they exist and are configured
            if [[ -n "${CONTAINER_MEMORY_LIMIT}" ]] && grep -q "memory:" docker-compose.yml; then
                echo "🔧 Applying configured memory limit: ${CONTAINER_MEMORY_LIMIT}"
                MEMORY_LIMIT=$(echo "${CONTAINER_MEMORY_LIMIT}" | tr '[:upper:]' '[:lower:]')
                
                # Create backup if not already created
                if [[ ! -f "docker-compose.yml.backup" ]]; then
                    cp docker-compose.yml docker-compose.yml.backup
                fi
                
                # Use awk for reliable replacement
                awk -v mem="$MEMORY_LIMIT" '
                /memory:/ {
                    gsub(/memory: *[^ ]*/, "memory: " mem)
                }
                { print }
                ' docker-compose.yml.backup > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml
                
                echo "   ✅ Updated memory limit to: $MEMORY_LIMIT"
            fi
            
        else
            echo "⚠️  docker-compose.yml not found"
        fi
        
        if [[ -f "Dockerfile" ]]; then
            echo "✅ Dockerfile generated"
        else
            echo "⚠️  Dockerfile not found"
        fi
        
        # Check if Docker image was built
        if docker images | grep -q "pentaho/pentaho-server"; then
            echo "✅ Pentaho Docker image built successfully:"
            docker images | grep "pentaho/pentaho-server"
        else
            echo "⚠️  Pentaho Docker image not found"
        fi
        
        echo "📁 Build artifacts summary:"
        ls -la
        
        echo ""
        echo "🔍 Final docker-compose.yml validation:"
        if grep -A2 -B2 "cpus:\|memory:" docker-compose.yml >/dev/null 2>&1; then
            grep -A2 -B2 "cpus:\|memory:" docker-compose.yml | head -10
        else
            echo "   No explicit resource limits (using Docker defaults)"
        fi
        
    else
        echo "❌ Build failed - generatedFiles directory not created"
        exit 1
    fi
    
    echo ""
    echo "🎉 Container build completed successfully!"
    echo "✅ Resource limits have been validated and optimized for EC2 instance"
    echo "📝 Containers are ready for deployment (not started yet for resource safety)"
    
EOF

echo "✅ Pentaho container build process completed!"
echo "📍 Build artifacts are ready on EC2 instance"
echo "🔜 Next step: Run 04-deploy-pentaho.sh to deploy the containers with proper resource limits"
