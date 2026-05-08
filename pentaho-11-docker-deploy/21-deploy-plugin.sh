#!/bin/bash

# Plugin Deployment Script - Downloads plugins from Artifactory and installs them
# Similar to 10-deploy-pentaho.sh but for plugins

set -e

# Parse optional --no-restart flag
NO_RESTART=false
if [[ "$1" == "--no-restart" ]]; then
    NO_RESTART=true
    shift
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 [--no-restart] <env-file> <plugin-url-or-name>"
    echo ""
    echo "For TYPICAL plugins, provide the full URL:"
    echo "  Example: $0 pentaho-deployment-sample-11-1-0-0-120.env https://one.hitachivantara.com/.../pdd-plugin-ee/11.1.0.0-120/pdd-plugin-ee-11.1.0.0-120.zip"
    echo ""
    echo "For SPECIAL plugins, provide just the name:"
    echo "  Example: $0 pentaho-deployment-sample-11-1-0-0-120.env webttle-plugins-ee-client"
    echo ""
    echo "Options:"
    echo "  --no-restart    Skip server restart (useful when deploying multiple plugins)"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
PLUGIN_INPUT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state file: env var > newest match > legacy derivation
if [ -n "${STATE_FILE:-}" ]; then
    STATE_FILE_NAME="$(basename "$STATE_FILE")"
else
    _found=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
    STATE_FILE_NAME="${_found:+$(basename "$_found")}"
    STATE_FILE_NAME="${STATE_FILE_NAME:-${ENV_FILE_NAME%.env}-runtime.state}"
fi

# Load environment variables
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"

if [ ! -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ Error: Runtime state not found. Run 01-create-pentaho-ec2.sh first"
    exit 1
fi

source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

echo "🚀 Pentaho Plugin Deployment"
echo "===================================="
echo "📋 Environment: ${ENVIRONMENT}"
echo "📋 Version: ${PENTAHO_VERSION}"
echo "📋 EC2 Instance: ${SSH_IP}"
echo ""

# Determine if input is a URL or a plugin name
PLUGIN_URL=""
PLUGIN_NAME=""
IS_SPECIAL=false
IS_LOCAL_FILE=false

if [[ "$PLUGIN_INPUT" =~ ^https?:// ]]; then
    # Input is a URL (normal plugin)
    PLUGIN_URL="$PLUGIN_INPUT"
    PLUGIN_FILENAME=$(basename "$PLUGIN_URL")
    PLUGIN_NAME="${PLUGIN_FILENAME%.zip}"  # Remove .zip extension for display
    echo "📦 Installing NORMAL plugin from URL"
    echo "   URL: ${PLUGIN_URL}"
    echo "   Filename: ${PLUGIN_FILENAME}"
else
    # Input is a plugin name (special plugin)
    PLUGIN_NAME="$PLUGIN_INPUT"
    IS_SPECIAL=true
    
    # Look up the special plugin URL from PLUGINS_SPECIAL
    while IFS='|' read -r name url; do
        name=$(echo "$name" | xargs)
        url=$(echo "$url" | xargs)
        [[ -z "$name" ]] && continue
        
        if [[ "$name" == "$PLUGIN_NAME" ]]; then
            # Expand any embedded variables like ${PENTAHO_VERSION}
            eval "PLUGIN_URL=\"$url\""
            PLUGIN_FILENAME=$(basename "$PLUGIN_URL")
            
            # Check if it's a local file reference
            if [[ "$PLUGIN_URL" =~ ^file:// ]]; then
                IS_LOCAL_FILE=true
                LOCAL_FILENAME="${PLUGIN_URL#file://}"
                PLUGIN_FILENAME="$LOCAL_FILENAME"
            fi
            break
        fi
    done <<< "$PLUGINS_SPECIAL"
    
    if [[ -z "$PLUGIN_URL" ]]; then
        echo "❌ Error: Special plugin '${PLUGIN_NAME}' not found in PLUGINS_SPECIAL configuration"
        echo ""
        echo "Available special plugins:"
        while IFS='|' read -r name url; do
            name=$(echo "$name" | xargs)
            [[ -z "$name" ]] && continue
            echo "  - $name"
        done <<< "$PLUGINS_SPECIAL"
        exit 1
    fi
    
    if [ "$IS_LOCAL_FILE" = true ]; then
        echo "📦 Installing SPECIAL plugin from LOCAL file: ${PLUGIN_NAME}"
        echo "   Local file: ${PLUGIN_FILENAME}"
        echo "   Handler: Custom installation logic"
    else
        echo "📦 Installing SPECIAL plugin: ${PLUGIN_NAME}"
        echo "   URL: ${PLUGIN_URL}"
        echo "   Filename: ${PLUGIN_FILENAME}"
        echo "   Handler: Custom installation logic"
    fi
fi
echo ""

echo "🔍 Testing SSH connection..."
if ! ssh -i "${KEY_PATH}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} echo "Connected" 2>/dev/null; then
    echo "❌ Cannot connect to EC2 instance"
    exit 1
fi
echo "✅ SSH connection verified"
echo ""

if [ "$IS_LOCAL_FILE" = true ]; then
    echo "📤 Step 1: Uploading Local Plugin File"
    echo "======================================="
    echo ""
    
    # Local plugin path
    PLUGIN_DIR="${SCRIPT_DIR}/downloads/plugins/${PENTAHO_VERSION}"
    PLUGIN_ZIP="${PLUGIN_DIR}/${PLUGIN_FILENAME}"
    
    if [ ! -f "$PLUGIN_ZIP" ]; then
        echo "❌ Local plugin file not found: $PLUGIN_ZIP"
        echo "   Expected location: ${PLUGIN_DIR}"
        exit 1
    fi
    
    echo "✅ Found local plugin: $PLUGIN_ZIP"
    
    # Create remote staging directory
    echo "🧭 Creating remote staging directory..."
    REMOTE_STAGING_DIR=$(ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "bash -s" <<'ENSURETMP'
set -e
if [ -d /mnt/pentaho-data ]; then
    sudo mkdir -p /mnt/pentaho-data/tmp || true
    sudo chmod 1777 /mnt/pentaho-data/tmp || true
    echo "/mnt/pentaho-data/tmp"
else
    mkdir -p /tmp || true
    echo "/tmp"
fi
ENSURETMP
)
    
    echo "📤 Uploading to server (staging: ${REMOTE_STAGING_DIR})..."
    scp -i "${KEY_PATH}" -o StrictHostKeyChecking=no "$PLUGIN_ZIP" ${SSH_USER}@${SSH_IP}:"${REMOTE_STAGING_DIR}/"
    
    echo "✅ Upload complete!"
    echo ""
else
    echo "📥 Step 1: Downloading Plugin from Artifactory"
    echo "================================================"
    echo ""

    # Create download script with embedded heredoc
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/pentaho/download-plugin.sh" << DOWNLOAD_SCRIPT
#!/bin/bash
set -e
cd /home/${SSH_USER}/pentaho

JFROG_TOKEN="${JFROG_TOKEN}"
PLUGIN_URL="${PLUGIN_URL}"
PLUGIN_ZIP_FILENAME="${PLUGIN_FILENAME}"

echo "🔍 Plugin details:"
echo "   URL: \${PLUGIN_URL}"
echo "   Filename: \${PLUGIN_ZIP_FILENAME}"
echo ""

download_plugin() {
    local url="\${PLUGIN_URL}"
    local min_size=10240  # 10KB minimum (plugins can be smaller than pentaho server)
    
    echo "🔍 [DEBUG] Attempting download:"
    echo "   URL: \${url}"
    echo "   Target file: \${PLUGIN_ZIP_FILENAME}"
    
    if [ -f "\${PLUGIN_ZIP_FILENAME}" ]; then
        local filesize=\$(stat -c%s "\${PLUGIN_ZIP_FILENAME}" 2>/dev/null)
        if [ "\${filesize:-0}" -gt "\${min_size}" ]; then
            echo "✅ \${PLUGIN_ZIP_FILENAME} exists and is valid size (\${filesize} bytes, skipping)"
            return 0
        else
            echo "⚠️  \${PLUGIN_ZIP_FILENAME} exists but is too small (\${filesize} bytes), re-downloading..."
            rm -f "\${PLUGIN_ZIP_FILENAME}"
        fi
    fi
    
    echo "📦 Downloading \${PLUGIN_ZIP_FILENAME}..."
    echo "🔍 [DEBUG] Full curl command:"
    echo "   curl -f -L -H 'X-JFrog-Art-Api: [TOKEN]' --progress-bar '\${url}' -o '\${PLUGIN_ZIP_FILENAME}'"
    
    if curl -f -L -H "X-JFrog-Art-Api: \${JFROG_TOKEN}" --progress-bar "\${url}" -o "\${PLUGIN_ZIP_FILENAME}"; then
        echo "✅ Downloaded \${PLUGIN_ZIP_FILENAME}"
        ls -lh "\${PLUGIN_ZIP_FILENAME}"
        return 0
    else
        local curl_exit=\$?
        echo "❌ Failed: \${PLUGIN_ZIP_FILENAME}"
        echo "🔍 [DEBUG] Curl exit code: \${curl_exit}"
        echo "🔍 [DEBUG] URL attempted: \${url}"
        echo "🔍 [DEBUG] Checking if partial file exists..."
        ls -lh "\${PLUGIN_ZIP_FILENAME}" 2>/dev/null || echo "   No partial file found"
        echo "🔍 [DEBUG] Testing JFrog connection..."
        curl -I -H "X-JFrog-Art-Api: \${JFROG_TOKEN}" "\${PLUGIN_BASE_URL}/\${PENTAHO_VERSION}/" 2>&1 | head -5 || echo "   Connection test failed"
        return 1
    fi
}

download_plugin
echo "✅ Download complete"
ls -lh \${PLUGIN_ZIP_FILENAME} 2>/dev/null || true
DOWNLOAD_SCRIPT

    # Execute download script
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
        "chmod +x /home/${SSH_USER}/pentaho/download-plugin.sh && /home/${SSH_USER}/pentaho/download-plugin.sh"

    echo ""
    echo "✅ Download complete!"
    echo ""
fi

echo "🔧 Step 2: Installing Plugin"
echo "============================="
echo ""

# Create installation script
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "export PENTAHO_VERSION='${PENTAHO_VERSION}'; export PLUGIN_NAME='${PLUGIN_NAME}'; export PLUGIN_ZIP_FILENAME='${PLUGIN_FILENAME}'; export DB_TYPE='${DB_TYPE}'; export IS_SPECIAL='${IS_SPECIAL}'; export IS_LOCAL_FILE='${IS_LOCAL_FILE}'; export STAGING_DIR='${REMOTE_STAGING_DIR:-/tmp}'; bash -s" <<ENDSSH
set -e

# Determine source directory based on whether file is local or downloaded
if [ "\${IS_LOCAL_FILE}" = "true" ]; then
    cd "\${STAGING_DIR}"
    echo "[INFO] Using local file from staging: \${STAGING_DIR}"
else
    cd /home/${SSH_USER}/pentaho
    echo "[INFO] Using downloaded file from: /home/${SSH_USER}/pentaho"
fi

# Prefer a docker tmp dir on data volume when available
if [ -d /mnt/pentaho-data ]; then
    export DOCKER_TMPDIR=/mnt/pentaho-data/docker-tmp
    sudo mkdir -p /mnt/pentaho-data/docker-tmp || true
    sudo chmod 1777 /mnt/pentaho-data/docker-tmp || true
else
    unset DOCKER_TMPDIR
fi

echo "[DEBUG] docker ps output:"
docker ps --format '{{.ID}} {{.Names}}'
echo "[DEBUG] grep/awk result:"
CONTAINER_ID=\$(docker ps --format '{{.ID}} {{.Names}}' | grep pentaho-server-\${DB_TYPE}-pentaho-server | awk '{print \$1}')
docker ps --format '{{.ID}} {{.Names}}' | grep pentaho-server-\${DB_TYPE}-pentaho-server | awk '{print \$1}'
if [ -z "\$CONTAINER_ID" ]; then
    echo "❌ Pentaho container not found for DB type: \${DB_TYPE}"
    exit 1
fi

echo "[DEBUG] Container status:"
CONTAINER_STATUS=\$(docker inspect -f '{{.State.Status}}' "\$CONTAINER_ID")
echo "\$CONTAINER_STATUS"
if [ "\$CONTAINER_STATUS" != "running" ]; then
    echo "❌ Pentaho container \$CONTAINER_ID is not running (status: \$CONTAINER_STATUS). Aborting."
    exit 1
fi

echo "[DEBUG] Checking /tmp in container..."
docker exec "\$CONTAINER_ID" bash -c "ls -ld /tmp || mkdir -p /tmp"

echo "[DEBUG] Copying plugin zip into container..."
docker cp "\$PLUGIN_ZIP_FILENAME" "\$CONTAINER_ID":/tmp/

echo "[DEBUG] Checking/installing unzip in container..."
docker exec -u 0 "\$CONTAINER_ID" bash -c "command -v unzip >/dev/null 2>&1 || (apt-get update && apt-get install -y unzip)"

echo "[DEBUG] Listing contents of zip before extraction..."
docker exec "\$CONTAINER_ID" bash -c "cd /tmp && unzip -l \$PLUGIN_ZIP_FILENAME"

echo "[DEBUG] Extracting plugin zip in container..."

if [ "\${IS_SPECIAL}" = "true" ]; then
    echo "[INFO] Using SPECIAL installation handler for: \${PLUGIN_NAME}"
    
    # Special plugin handlers - add new cases here for new special plugins
    case "\${PLUGIN_NAME}" in
        webttle-plugins-ee-client)
            echo "[SPECIAL] Webttle: Extracting to /opt/pentaho/"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "unzip -o /tmp/\$PLUGIN_ZIP_FILENAME -d /opt/pentaho/"
            echo "[SPECIAL] Webttle: Setting ownership"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/"
            echo "[SPECIAL] Webttle: Listing files"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "ls -l /opt/pentaho/"
            ;;
        pentaho-app-shell-core-webclient)
            echo "[SPECIAL] App Shell: Creating directory and extracting"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "mkdir -p /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell && unzip -o /tmp/\$PLUGIN_ZIP_FILENAME -d /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
            echo "[SPECIAL] App Shell: Setting ownership"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
            echo "[SPECIAL] App Shell: Listing files"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "ls -l /opt/pentaho/pentaho-server/pentaho-solutions/system/app-shell"
            ;;
        semantic-model-editor)
            echo "[SPECIAL] Semantic Model Editor: Standard system folder installation"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "unzip -o /tmp/\$PLUGIN_ZIP_FILENAME -d /opt/pentaho/pentaho-server/pentaho-solutions/system"
            echo "[SPECIAL] Semantic Model Editor: Setting ownership"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/pentaho-server/pentaho-solutions/system"
            echo "[SPECIAL] Semantic Model Editor: Listing files"
            docker exec -u 0 "\$CONTAINER_ID" bash -c "ls -l /opt/pentaho/pentaho-server/pentaho-solutions/system"
            ;;
        *)
            echo "[ERROR] Unknown special plugin: \${PLUGIN_NAME}"
            echo "[ERROR] Add handler code to 21-deploy-plugin.sh for this plugin"
            exit 1
            ;;
    esac
else
    echo "[INFO] Using NORMAL installation (extract to system folder)"
    docker exec -u 0 "\$CONTAINER_ID" bash -c "unzip -o /tmp/\$PLUGIN_ZIP_FILENAME -d /opt/pentaho/pentaho-server/pentaho-solutions/system"
    echo "[DEBUG] Setting ownership to pentaho:pentaho for /opt/pentaho/pentaho-server/pentaho-solutions/system after extraction..."
    docker exec -u 0 "\$CONTAINER_ID" bash -c "chown -R pentaho:pentaho /opt/pentaho/pentaho-server/pentaho-solutions/system"
    echo "[DEBUG] Listing /opt/pentaho/pentaho-server/pentaho-solutions/system after extraction and chown..."
    docker exec -u 0 "\$CONTAINER_ID" bash -c "ls -l /opt/pentaho/pentaho-server/pentaho-solutions/system"
fi

# Copy step fallback (kept for backward compatibility)
docker exec -u 0 "\$CONTAINER_ID" bash -c "cd /opt/pentaho/pentaho-server/pentaho-solutions/system && cp -r \$PLUGIN_ZIP_FILENAME/pentaho-server/* /opt/pentaho/pentaho-server/ 2>/dev/null || echo '[DEBUG] cp command skipped, adjust path as needed.'"

# Clear Karaf cache
docker exec -u 0 "\$CONTAINER_ID" bash -c "rm -rf /opt/pentaho/pentaho-server/pentaho-solutions/system/karaf/caches/*"

echo "[DEBUG] Cleaning up temporary files..."
# Clean up the plugin zip from container /tmp
docker exec -u 0 "\$CONTAINER_ID" bash -c "rm -f /tmp/\$PLUGIN_ZIP_FILENAME"
# Clean up any extraction artifacts in /tmp
docker exec -u 0 "\$CONTAINER_ID" bash -c "rm -rf /tmp/*plugin* /tmp/unzip* 2>/dev/null || true"
# Clean up the plugin zip from host (different paths for local vs downloaded)
if [ "\${IS_LOCAL_FILE}" = "true" ]; then
    rm -f "\${STAGING_DIR}/\$PLUGIN_ZIP_FILENAME" 2>/dev/null || true
else
    rm -f "\$PLUGIN_ZIP_FILENAME" 2>/dev/null || true
fi
echo "[DEBUG] Cleanup complete."
ENDSSH

if [ "${NO_RESTART}" = true ]; then
    echo ""
    echo "✅ Plugin ${PLUGIN_NAME} installed successfully"
    echo "⚠️  Server restart skipped (--no-restart flag used)"
    echo ""
else
    # Restart the Pentaho container
    echo ""
    echo "🔄 Restarting Pentaho server..."
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "docker restart \$(docker ps -q -f name=pentaho-server)"
    echo ""
    echo "🎉 Plugin Deployment Complete!"
    echo ""
    echo "✅ Plugin ${PLUGIN_NAME} installed and Pentaho server restarted"
    echo "🌐 Access: http://${SSH_IP}/pentaho"
    echo "👤 Login: admin/password"
    echo ""
fi
