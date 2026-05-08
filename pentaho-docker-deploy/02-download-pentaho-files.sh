#!/bin/bash
# 02-download-pentaho-files.sh
# Download Pentaho installation files and DockMaker tool to EC2 instance

set -e

# Configuration
ENVIRONMENT=${1}
PENTAHO_VERSION="10.2.0.0"

# Validate environment parameter
if [ -z "$ENVIRONMENT" ]; then
    echo "❌ Environment parameter required"
    echo "Usage: $0 [environment-name]"
    echo "Example: $0 dev"
    exit 1
fi

# Load deployment configuration and runtime state
if [ -f "pentaho-deployment-${ENVIRONMENT}.env" ]; then
    source "pentaho-deployment-${ENVIRONMENT}.env"
else
    echo "❌ Configuration not found: pentaho-deployment-${ENVIRONMENT}.env"
    echo "Please check your environment configuration"
    exit 1
fi

if [ -f "pentaho-deployment-${ENVIRONMENT}-runtime.state" ]; then
    source "pentaho-deployment-${ENVIRONMENT}-runtime.state"
else
    echo "❌ Runtime state not found: pentaho-deployment-${ENVIRONMENT}-runtime.state"
    echo "Please run 01-create-pentaho-ec2.sh first to create the EC2 instance"
    exit 1
fi

echo "🚀 Downloading Pentaho files to EC2 instance..."
echo "Environment: ${ENVIRONMENT}"
echo "Instance: ${INSTANCE_ID} (${PRIVATE_IP})"
echo ""

# Check if instance is accessible
echo "🔍 Checking EC2 instance accessibility..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} "echo 'Connection successful'" >/dev/null 2>&1; then
    echo "❌ Error: Cannot connect to EC2 instance at ${PRIVATE_IP}"
    echo "Make sure:"
    echo "  1. Instance is running and accessible"
    echo "  2. Private IP is correct (for private subnet)"
    echo "  3. SSH key path is correct: ${KEY_PATH}"
    echo "  4. Security group allows SSH from your location"
    echo "  5. SSH user is correct: ${SSH_USER}"
    exit 1
fi

echo "✅ EC2 instance is accessible"

# Check if user-data script completed successfully
echo "🔍 Checking user-data script completion..."
USER_DATA_STATUS=$(ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} '
    # Check if user-data log exists and completed
    if [ -f /var/log/cloud-init-output.log ]; then
        if tail -10 /var/log/cloud-init-output.log | grep -q "Cloud-init.*finished\|setup.*complete"; then
            echo "COMPLETED"
        else
            echo "IN_PROGRESS"
        fi
    else
        echo "NOT_STARTED"
    fi
' 2>/dev/null)

if [ "$USER_DATA_STATUS" = "IN_PROGRESS" ] || [ "$USER_DATA_STATUS" = "NOT_STARTED" ]; then
    echo "⏳ User-data script still running. Waiting for completion..."
    echo "   This includes Docker installation, Java setup, and directory creation."
    echo "   Please wait 2-3 minutes and try again."
    echo ""
    echo "🔍 To check progress manually:"
    echo "   ssh -i ${KEY_PATH} ${SSH_USER}@${PRIVATE_IP} 'sudo tail -f /var/log/cloud-init-output.log'"
    exit 1
elif [ "$USER_DATA_STATUS" = "COMPLETED" ]; then
    echo "✅ User-data script completed successfully"
else
    echo "⚠️  Cannot determine user-data status, continuing anyway..."
fi

# Verify essential components are available
echo "🔍 Verifying essential components..."
COMPONENT_CHECK=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} '
    MISSING=""
    command -v docker >/dev/null 2>&1 || MISSING="$MISSING docker"
    command -v java >/dev/null 2>&1 || MISSING="$MISSING java"
    [ -d "/home/'${SSH_USER}'/pentaho" ] || MISSING="$MISSING pentaho-dirs"
    echo "$MISSING"
' 2>/dev/null)

if [ -n "$COMPONENT_CHECK" ]; then
    echo "❌ Missing essential components:$COMPONENT_CHECK"
    echo "   User-data script may not have completed successfully."
    echo "   Please wait a few more minutes and try again."
    exit 1
fi

echo "✅ All essential components ready (Docker, Java, directories)"

# Verify Docker is using EBS volume correctly
echo "🔍 Verifying Docker configuration..."
DOCKER_CHECK=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} '
    # Check Docker root directory
    DOCKER_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | cut -d":" -f2 | xargs || echo "")
    if [[ "$DOCKER_ROOT" == *"/mnt/pentaho-data/docker"* ]]; then
        echo "EBS_VOLUME_CONFIGURED"
    else
        echo "ROOT_VOLUME:$DOCKER_ROOT"
    fi
' 2>/dev/null)

if [ "$DOCKER_CHECK" = "EBS_VOLUME_CONFIGURED" ]; then
    echo "✅ Docker is correctly configured to use EBS volume"
elif [[ "$DOCKER_CHECK" == "ROOT_VOLUME:"* ]]; then
    CURRENT_ROOT=$(echo "$DOCKER_CHECK" | cut -d":" -f2-)
    echo "⚠️  Docker is using root volume instead of EBS volume"
    echo "   Current Docker Root: $CURRENT_ROOT"
    echo "   Expected: /mnt/pentaho-data/docker"
    echo "   This will be verified and fixed in step 3 if needed"
else
    echo "⚠️  Unable to determine Docker configuration"
fi

# Create transfer script for Pentaho files
cat > transfer-pentaho-files.sh << 'TRANSFER_EOF'
#!/bin/bash
set -e

PRIVATE_IP=$1
KEY_PATH=$2
PENTAHO_VERSION=${3:-"10.2.0.0"}
SSH_USER=${4:-"ubuntu"}

echo "📦 Transferring Pentaho files..."

# Check if local downloads exist (you'll need to download these manually from Pentaho Support Portal)
LOCAL_DOWNLOADS_DIR="./pentaho-downloads"

if [ ! -d "${LOCAL_DOWNLOADS_DIR}" ]; then
    echo "⚠️  Local downloads directory not found: ${LOCAL_DOWNLOADS_DIR}"
    echo ""
    echo "📋 MANUAL DOWNLOAD REQUIRED:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Go to https://support.pentaho.com/hc/en-us"
    echo "2. Sign in with your Pentaho support credentials"
    echo "3. Navigate: Downloads > 10.x > Pentaho 10.2 GA Release"
    echo "4. Download the following files to ${LOCAL_DOWNLOADS_DIR}/:"
    echo "   • pdi-ee-${PENTAHO_VERSION}*.zip (PDI Enterprise) OR paz-plugin-ee-${PENTAHO_VERSION}*.zip (PDI Plugins)"
    echo "   • pentaho-server-ee-${PENTAHO_VERSION}*.zip (Server Enterprise)"
    echo "   • dock-maker-${PENTAHO_VERSION}-*.zip (DockMaker Tool)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "5. Re-run this script after downloading the files"
    
    mkdir -p "${LOCAL_DOWNLOADS_DIR}"
    cat > "${LOCAL_DOWNLOADS_DIR}/README.md" << 'README_EOF'
# Pentaho Downloads Directory

Download the following files from the Pentaho Support Portal to this directory:

## Required Files:
- `pdi-ee-10.2.0.0-*.zip` - Pentaho Data Integration Enterprise Edition
- `pentaho-server-ee-10.2.0.0-*.zip` - Pentaho Server Enterprise Edition  
- `dock-maker-10.2.0.0-*.zip` - DockMaker Tool
- `paz-plugin-ee-10.2.0.0-*.zip` - PDI Enterprise Plugins (alternative to core PDI)

## Download Source:
1. Go to: https://support.pentaho.com/hc/en-us
2. Sign in with Pentaho support credentials
3. Navigate: Downloads > 10.x > Pentaho 10.2 GA Release
4. Download files to this directory
README_EOF
    
    exit 1
fi

# Check for required files
echo "🔍 Checking for required Pentaho files..."
REQUIRED_FILES=()
DOCK_MAKER_FILE=""

# Look for DockMaker tool
DOCK_MAKER_FILE=$(ls ${LOCAL_DOWNLOADS_DIR}/dock-maker-${PENTAHO_VERSION}*.zip 2>/dev/null | head -1 || echo "")
if [ -z "$DOCK_MAKER_FILE" ]; then
    echo "❌ DockMaker tool not found: dock-maker-${PENTAHO_VERSION}-*.zip"
    exit 1
fi
REQUIRED_FILES+=("$DOCK_MAKER_FILE")

# Look for PDI/PAZ Enterprise Edition only (handle build numbers)
PDI_FILE=""
# Look for Enterprise Edition with various patterns
PDI_EE_FILES=$(ls ${LOCAL_DOWNLOADS_DIR}/p*{di,az}*-ee-${PENTAHO_VERSION}*.zip 2>/dev/null | head -1)
if [ -n "$PDI_EE_FILES" ]; then
    PDI_FILE="$PDI_EE_FILES"
    # Check if it's a plugin file or core PDI
    if [[ "$(basename $PDI_FILE)" == *"plugin"* ]]; then
        echo "✅ Found PDI Enterprise Plugins: $(basename $PDI_FILE)"
    else
        echo "✅ Found PDI Enterprise Edition: $(basename $PDI_FILE)"
    fi
else
    echo "❌ PDI Enterprise installation file not found"
    echo "Looking for: p*{di,az}*-ee-${PENTAHO_VERSION}*.zip (Enterprise Edition only)"
    exit 1
fi
REQUIRED_FILES+=("$PDI_FILE")

# Look for Pentaho Server Enterprise Edition only (handle build numbers)
SERVER_FILE=""
SERVER_EE_FILES=$(ls ${LOCAL_DOWNLOADS_DIR}/pentaho-server-ee-${PENTAHO_VERSION}*.zip 2>/dev/null | head -1)
if [ -n "$SERVER_EE_FILES" ]; then
    SERVER_FILE="$SERVER_EE_FILES"
    echo "✅ Found Pentaho Server Enterprise Edition: $(basename $SERVER_FILE)"
else
    echo "❌ Pentaho Server Enterprise installation file not found"
    echo "Looking for: pentaho-server-ee-${PENTAHO_VERSION}*.zip (Enterprise Edition only)"
    exit 1
fi
REQUIRED_FILES+=("$SERVER_FILE")

echo "✅ All required files found"

# Create directory structure on EC2 first
echo "🏗️ Creating directory structure on EC2 instance..."
ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} "mkdir -p /home/${SSH_USER}/pentaho/{downloads,dockmaker,workspace}"

# Transfer files to EC2
echo "📤 Transferring files to EC2 instance..."
scp -o StrictHostKeyChecking=no -i "${KEY_PATH}" "${REQUIRED_FILES[@]}" ${SSH_USER}@${PRIVATE_IP}:/home/${SSH_USER}/pentaho/downloads/

echo "✅ Files transferred successfully"
TRANSFER_EOF

chmod +x transfer-pentaho-files.sh

# Execute the transfer
./transfer-pentaho-files.sh "${PRIVATE_IP}" "${KEY_PATH}" "${PENTAHO_VERSION}" "${SSH_USER}"

# Create setup script on EC2 instance
echo "📝 Setting up Pentaho downloads on EC2 instance..."
cat > setup-pentaho-downloads.sh << SETUP_EOF
#!/bin/bash
set -e

PENTAHO_VERSION="10.2.0.0"
DOWNLOADS_DIR="/home/${SSH_USER}/pentaho/downloads"
DOCKMAKER_DIR="/home/${SSH_USER}/pentaho/dockmaker"
WORKSPACE_DIR="/home/${SSH_USER}/pentaho/workspace"

echo "🔧 Setting up Pentaho downloads on EC2..."

# Install docker-compose if not already installed
echo "🔍 Checking docker-compose installation..."
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "📦 Installing docker-compose via apt..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
    
    # Create symlink for backward compatibility
    if [ ! -f /usr/local/bin/docker-compose ]; then
        sudo ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose || true
    fi
    
    if docker compose version || docker-compose --version; then
        echo "✅ docker-compose installed successfully"
    else
        echo "❌ docker-compose installation failed"
        exit 1
    fi
elif ! docker-compose --version >/dev/null 2>&1; then
    echo "⚠️  docker-compose corrupted, reinstalling via apt..."
    sudo rm -f /usr/local/bin/docker-compose
    sudo apt-get update
    sudo apt-get install -y --reinstall docker-compose-plugin
    
    # Create symlink for backward compatibility
    if [ ! -f /usr/local/bin/docker-compose ]; then
        sudo ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose || true
    fi
    
    if docker compose version || docker-compose --version; then
        echo "✅ docker-compose reinstalled successfully"
    else
        echo "❌ docker-compose reinstallation failed"
        exit 1
    fi
else
    echo "✅ docker-compose is working correctly"
fi

cd /home/${SSH_USER}/pentaho

# Extract DockMaker tool
echo "📦 Extracting DockMaker tool..."
DOCK_MAKER_ZIP=\$(ls downloads/dock-maker-\${PENTAHO_VERSION}*.zip | head -1)
unzip -q "\$DOCK_MAKER_ZIP" -d dockmaker/

# Find and set permissions on DockMaker scripts
DOCKMAKER_EXTRACTED_DIR=\$(find dockmaker/ -name "DockMaker.sh" -type f | head -1 | xargs dirname)
if [ -n "\$DOCKMAKER_EXTRACTED_DIR" ]; then
    chmod +x "\$DOCKMAKER_EXTRACTED_DIR/DockMaker.sh" "\$DOCKMAKER_EXTRACTED_DIR/DockMakerDown.sh" 2>/dev/null || true
    echo "✅ DockMaker tool extracted to: \$DOCKMAKER_EXTRACTED_DIR"
    
    # Copy artifacts to DockMaker artifactCache directory
    echo "📦 Copying artifacts to DockMaker artifactCache..."
    PENTAHO_SERVER_ZIP=\$(ls downloads/pentaho-server-ee-\${PENTAHO_VERSION}*.zip | head -1)
    PAZ_PLUGIN_ZIP=\$(ls downloads/paz-plugin-ee-\${PENTAHO_VERSION}*.zip 2>/dev/null | head -1)
    
    if [ -f "\$PENTAHO_SERVER_ZIP" ]; then
        cp "\$PENTAHO_SERVER_ZIP" "\$DOCKMAKER_EXTRACTED_DIR/artifactCache/"
        echo "✅ Copied Pentaho Server to artifactCache"
    fi
    
    if [ -f "\$PAZ_PLUGIN_ZIP" ]; then
        cp "\$PAZ_PLUGIN_ZIP" "\$DOCKMAKER_EXTRACTED_DIR/artifactCache/"
        echo "✅ Copied PAZ Plugin to artifactCache"
    fi
    
else
    echo "❌ DockMaker extraction failed - DockMaker.sh not found"
    exit 1
fi

# Prepare workspace directories
echo "📁 Creating workspace directories..."
mkdir -p workspace/{pdi,server,generatedFiles}

echo "✅ Setup completed successfully!"
SETUP_EOF

# Transfer and execute setup script in smaller steps to avoid kill signals
echo "📤 Transferring setup script to EC2..."
scp -o StrictHostKeyChecking=no -i "${KEY_PATH}" setup-pentaho-downloads.sh ${SSH_USER}@${PRIVATE_IP}:/home/${SSH_USER}/

echo "🔧 Making setup script executable..."
ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} "chmod +x setup-pentaho-downloads.sh"

echo "⚙️ Running setup on EC2 (this may take a moment)..."
ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} "./setup-pentaho-downloads.sh"

# Verify setup completed successfully
echo "🔍 Verifying setup completion..."
ssh -o StrictHostKeyChecking=no -i "${KEY_PATH}" ${SSH_USER}@${PRIVATE_IP} "
    echo '📋 Setup Verification:'
    echo '   DockMaker: '\$(find /home/${SSH_USER}/pentaho/dockmaker -name \"DockMaker.sh\" -type f | head -1 || echo \"NOT FOUND\")
    echo '   PDI file: '\$(ls /home/${SSH_USER}/pentaho/downloads/p*-ee-*.zip 2>/dev/null | head -1 || echo \"NOT FOUND\")
    echo '   Server file: '\$(ls /home/${SSH_USER}/pentaho/downloads/pentaho-server-ee-*.zip 2>/dev/null | head -1 || echo \"NOT FOUND\")
    echo '   Workspace: '\$(ls -d /home/${SSH_USER}/pentaho/workspace 2>/dev/null || echo \"NOT FOUND\")
"

# Clean up local temp files
rm -f transfer-pentaho-files.sh setup-pentaho-downloads.sh

echo ""
echo "🎉 Pentaho files downloaded and configured successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Next Steps:"
echo "1. Connect to EC2: ssh -i ${KEY_PATH} ${SSH_USER}@${PRIVATE_IP}"
echo "2. Run: cd /home/${SSH_USER}/pentaho"
echo "3. Run: ../03-build-pentaho-containers.sh"
echo ""
echo "📊 To check installation status:"
echo "ssh -i ${KEY_PATH} ${SSH_USER}@${PRIVATE_IP} 'cat /home/${SSH_USER}/pentaho/installation-inventory.txt'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
