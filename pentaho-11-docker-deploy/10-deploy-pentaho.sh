#!/bin/bash

# Simplified Pentaho 11 Deployment Script  
# Downloads images, extracts on-prem distribution, and deploys with docker-compose


set -e

# Database type: set default to 'postgres', override with env or CLI arg if desired
DB_TYPE="postgres"
# Optionally allow override via environment or CLI
if [ -n "$PENTAHO_DB_TYPE" ]; then
    DB_TYPE="$PENTAHO_DB_TYPE"
fi
if [ -n "$2" ]; then
    DB_TYPE="$2"
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-dev.env"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-113.env"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state file: env var > newest match > legacy derivation
if [ -n "${STATE_FILE:-}" ]; then
    STATE_FILE_NAME="$(basename "$STATE_FILE")"
else
    _found=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
    STATE_FILE_NAME="${_found:+$(basename "$_found")}"
    STATE_FILE_NAME="${STATE_FILE_NAME:-${ENV_FILE_NAME%.env}-runtime.state}"
fi

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

echo "🚀 Pentaho 11 Simplified Deployment"
echo "===================================="
echo "📋 Environment: ${ENVIRONMENT}"
echo "📋 Version: ${PENTAHO_VERSION}"
echo "📋 EC2 Instance: ${SSH_IP}"
echo ""

echo "🔍 Testing SSH connection..."
if ! ssh -i "${KEY_PATH}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} echo "Connected" 2>/dev/null; then
    echo "❌ Cannot connect to EC2 instance"
    exit 1
fi
echo "✅ SSH connection verified"
echo ""

echo "📥 Step 1: Downloading to EC2"
echo "=============================="
echo ""

# Create download script with embedded heredoc (with variable expansion)
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/pentaho/download.sh" << DOWNLOAD_SCRIPT
#!/bin/bash
set -e
cd /home/${SSH_USER}/pentaho

JFROG_TOKEN="${JFROG_TOKEN}"
JFROG_BASE_URL="${JFROG_BASE_URL}"
PENTAHO_VERSION="${PENTAHO_VERSION}"

download_file() {
    local subdir=\$1
    local filename=\$2
    local url="\${JFROG_BASE_URL}/\${PENTAHO_VERSION}/\${subdir}/\${filename}"
    local min_size=1048576  # 1MB minimum
    
    if [ -f "\${filename}" ]; then
        local filesize=\$(stat -f%z "\${filename}" 2>/dev/null || stat -c%s "\${filename}" 2>/dev/null)
        if [ "\${filesize:-0}" -gt "\${min_size}" ]; then
            echo "✅ \${filename} already exists (\$(numfmt --to=iec \${filesize} 2>/dev/null || echo "\${filesize} bytes")), skipping"
            return 0
        else
            echo "⚠️  \${filename} exists but is too small, re-downloading..."
            rm -f "\${filename}"
        fi
    fi
    
    echo "📦 Downloading \${filename}..."
    
    # Get file size from Content-Length header for progress tracking
    local total_bytes=\$(curl -sI -f -L -H "X-JFrog-Art-Api: \${JFROG_TOKEN}" "\${url}" 2>/dev/null | grep -i content-length | tail -1 | tr -d '[:space:]' | cut -d: -f2)
    
    # Start download silently in background
    curl -f -L -s -H "X-JFrog-Art-Api: \${JFROG_TOKEN}" "\${url}" -o "\${filename}" &
    local curl_pid=\$!
    
    # Print clean progress while downloading
    if [ -n "\${total_bytes}" ] && [ "\${total_bytes}" -gt 0 ] 2>/dev/null; then
        local total_mb=\$(( total_bytes / 1048576 ))
        local last_pct=-1
        while kill -0 \${curl_pid} 2>/dev/null; do
            if [ -f "\${filename}" ]; then
                local cur=\$(stat -c%s "\${filename}" 2>/dev/null || stat -f%z "\${filename}" 2>/dev/null || echo 0)
                local pct=\$(( cur * 100 / total_bytes ))
                # Print every 10%
                if [ \$(( pct / 10 )) -gt \$(( last_pct / 10 )) ] 2>/dev/null; then
                    local cur_mb=\$(( cur / 1048576 ))
                    echo "   \${pct}%  (\${cur_mb}MB / \${total_mb}MB)"
                    last_pct=\${pct}
                fi
            fi
            sleep 2
        done
    else
        # No content-length available, just show a waiting indicator
        local dots=0
        while kill -0 \${curl_pid} 2>/dev/null; do
            dots=\$(( dots + 1 ))
            if [ \$(( dots % 5 )) -eq 0 ]; then
                echo "   still downloading..."
            fi
            sleep 2
        done
    fi
    
    wait \${curl_pid}
    local curl_exit=\$?
    
    if [ \${curl_exit} -eq 0 ] && [ -f "\${filename}" ]; then
        local filesize=\$(stat -f%z "\${filename}" 2>/dev/null || stat -c%s "\${filename}" 2>/dev/null)
        local human_size=\$(numfmt --to=iec \${filesize} 2>/dev/null || echo "\${filesize} bytes")
        
        # Verify it's not an HTML error page
        if file "\${filename}" | grep -q "HTML"; then
            echo "❌ Downloaded file appears to be HTML (error page), not a valid archive"
            rm -f "\${filename}"
            return 1
        fi
        
        echo "✅ Downloaded \${filename} (\${human_size})"
        return 0
    else
        echo "❌ Failed to download: \${filename} (exit code \${curl_exit})"
        rm -f "\${filename}" 2>/dev/null
        return 1
    fi
}

download_file "images" "pentaho-server-\${PENTAHO_VERSION}.tar.gz"
download_file "dists" "on-prem-\${PENTAHO_VERSION}.zip"
echo "✅ Downloads complete"
ls -lh *.tar.gz *.zip 2>/dev/null || true
DOWNLOAD_SCRIPT

# Execute download script
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
    "chmod +x /home/${SSH_USER}/pentaho/download.sh && /home/${SSH_USER}/pentaho/download.sh"

echo ""
echo "✅ Download complete!"
echo ""

echo "🚀 Step 2: Deploying Pentaho"
echo "============================="
echo ""

# Create deployment script (with variable expansion)
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/pentaho/deploy.sh" << DEPLOY_SCRIPT
#!/bin/bash
set -e
cd /home/${SSH_USER}/pentaho

PENTAHO_VERSION="${PENTAHO_VERSION}"
LICENSE_URL="${LICENSE_URL}"
PENTAHO_CONTAINER_CPU_LIMIT="${PENTAHO_CONTAINER_CPU_LIMIT}"
PENTAHO_CONTAINER_MEMORY_LIMIT="${PENTAHO_CONTAINER_MEMORY_LIMIT}"
DATABASE_CONTAINER_CPU_LIMIT="${DATABASE_CONTAINER_CPU_LIMIT}"
DATABASE_CONTAINER_MEMORY_LIMIT="${DATABASE_CONTAINER_MEMORY_LIMIT}"
PENTAHO_JVM_MIN_HEAP="${PENTAHO_JVM_MIN_HEAP}"
PENTAHO_JVM_MAX_HEAP="${PENTAHO_JVM_MAX_HEAP}"
DB_TYPE="${DB_TYPE}"

if [ -z "${DB_TYPE}" ]; then
    echo "[WARN] DB_TYPE not set; defaulting to 'postgres'"
    DB_TYPE="postgres"
fi
echo "[DEBUG] Using DB_TYPE='${DB_TYPE}'"

echo "🐳 Checking Docker image..."
IMAGE_NAME="one.hitachivantara.com/pntprv-docker-dev/pentaho/pdia-image-configurator/pentaho-server:\${PENTAHO_VERSION}"

if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^\${IMAGE_NAME}\$"; then
    echo "✅ Image already loaded: \${IMAGE_NAME}"
else
    echo "📥 Loading Docker image from tar.gz..."
    docker load -i "pentaho-server-\${PENTAHO_VERSION}.tar.gz"
    
    # Check what image was actually loaded and tag it if necessary
    LOADED_IMAGE=\$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "pentaho-server:\${PENTAHO_VERSION}" | head -n1)
    if [ -n "\${LOADED_IMAGE}" ] && [ "\${LOADED_IMAGE}" != "\${IMAGE_NAME}" ]; then
        echo "🏷️  Tagging \${LOADED_IMAGE} as \${IMAGE_NAME}"
        docker tag "\${LOADED_IMAGE}" "\${IMAGE_NAME}"
    fi
    echo "✅ Image loaded successfully"
fi

echo "📋 Available Pentaho images:"
docker images | grep pentaho

echo "📦 Extracting distribution..."
sudo rm -rf onprem
unzip -q "on-prem-\${PENTAHO_VERSION}.zip" -d onprem
if [ ! -d onprem ]; then
    echo "❌ Extraction failed: onprem directory missing"; exit 1
fi
echo "📂 Extracted top-level (depth 3):"; find onprem -maxdepth 3 -type d -print | head -30

echo "⚙️  Configuring (auto-detect layout)..."
echo "[DEBUG] Locating compose file using known layout..."
BASE_DIR="onprem/dist/on-prem/pentaho-server"
# Try DB-specific directory first
DB_DIR="\${BASE_DIR}/pentaho-server-\${DB_TYPE}"
COMPOSE_FILE_NAME="docker-compose-\${DB_TYPE}.yaml"
if [ -d "\${DB_DIR}" ] && [ -f "\${DB_DIR}/\${COMPOSE_FILE_NAME}" ]; then
  cd "\${DB_DIR}" || { echo "❌ cd failed: \${DB_DIR}"; exit 1; }
  echo "✅ Using server dir: \$(pwd)"
else
  echo "[WARN] \${COMPOSE_FILE_NAME} not found in \${DB_DIR}. Scanning for any compose files..."
  COMPOSE_PATH=\$(find "\${BASE_DIR}" -maxdepth 3 -type f -name 'docker-compose-*.yaml' -print | sort)
  if [ -z "\${COMPOSE_PATH}" ]; then
    echo "❌ No docker-compose-*.yaml under \${BASE_DIR}"; exit 1
  fi
  echo "📋 Found compose files:"; echo "\${COMPOSE_PATH}" | sed 's/^/   - /'
  PICK=\$(echo "\${COMPOSE_PATH}" | grep -E "docker-compose-\${DB_TYPE}\.yaml" | head -n1)
  [ -z "\${PICK}" ] && PICK=\$(echo "\${COMPOSE_PATH}" | grep -E 'docker-compose-mysql\.yaml' | head -n1)
  [ -z "\${PICK}" ] && PICK=\$(echo "\${COMPOSE_PATH}" | head -n1)
  COMPOSE_FILE_NAME=\$(basename "\${PICK}")
  TARGET_DIR=\$(dirname "\${PICK}")
  cd "\${TARGET_DIR}" || { echo "❌ cd failed: \${TARGET_DIR}"; exit 1; }
  DETECTED_DB=\$(echo "\${COMPOSE_FILE_NAME}" | sed -E 's/docker-compose-([^.]+)\.yaml/\1/')
  if [ -n "\${DETECTED_DB}" ] && [ "\${DB_TYPE}" != "\${DETECTED_DB}" ]; then
    echo "[INFO] Adjusting DB_TYPE to detected '\${DETECTED_DB}'"; DB_TYPE="\${DETECTED_DB}"
  fi
  echo "✅ Using server dir: \$(pwd)"
fi
echo "✅ Final compose file: \${COMPOSE_FILE_NAME} (DB_TYPE='\${DB_TYPE}')"

echo "🔍 Scanning compose for build contexts..."
BUILD_PATHS=\$(grep -E '^[[:space:]]*build:' "\${COMPOSE_FILE_NAME}" | sed -E "s/^[[:space:]]*build:[[:space:]]*//" | sed "s/[\"']//g" | sed 's#^\./##') || true
if [ -n "\${BUILD_PATHS}" ]; then
    echo "📋 Build contexts:"; echo "\${BUILD_PATHS}" | sed 's/^/   - /'
    MISSING=0
    while IFS= read -r ctx; do
        [ -z "\${ctx}" ] && continue
        if [ -d "\${ctx}" ]; then
            if [ ! -f "\${ctx}/Dockerfile" ]; then
                echo "❌ Missing Dockerfile in \${ctx}"; ls -la "\${ctx}" || true; MISSING=1
            else
                echo "✅ Dockerfile present in \${ctx}"
            fi
        else
            echo "❌ Build context dir not found: \${ctx}"; MISSING=1
        fi
    done <<< "\${BUILD_PATHS}"
    if [ \${MISSING} -ne 0 ]; then
        echo "🚫 Aborting due to missing Dockerfile(s). If bundle is image-only, remove build: sections."; exit 1
    fi
else
    echo "ℹ️ No build: contexts; using pre-built image(s)."
fi

# Backup original .env
[ -f .env ] && cp .env .env.backup

# Update only the specific variables we need to change
sed -i "s|PENTAHO_VERSION=.*|PENTAHO_VERSION=\${PENTAHO_VERSION}|g" .env
sed -i "s|LICENSE_URL=.*|LICENSE_URL=\${LICENSE_URL}|g" .env
sed -i "s|PORT=.*|PORT=80|g" .env
# Fix image name to match what we have loaded (RC vs DEV)
sed -i "s|PENTAHO_IMAGE_NAME=.*|PENTAHO_IMAGE_NAME=one.hitachivantara.com/pntprv-docker-dev/pentaho/pdia-image-configurator/pentaho-server|g" .env
# Update JVM heap memory settings
sed -i "s|JAVA_XMX=.*|JAVA_XMX=\${PENTAHO_JVM_MAX_HEAP}|g" .env
sed -i "s|JAVA_XMS=.*|JAVA_XMS=\${PENTAHO_JVM_MIN_HEAP}|g" .env

echo "📋 Updated .env file:"
cat .env

# Remove build sections from compose file since we're using pre-loaded images
echo ""
echo "🔧 Removing build: sections from compose file (using pre-loaded images)..."
if grep -q "^[[:space:]]*build:" "\${COMPOSE_FILE_NAME}"; then
    # Create backup
    cp "\${COMPOSE_FILE_NAME}" "\${COMPOSE_FILE_NAME}.bak"
    # Remove build: and its args: sub-section
    sed -i '/^[[:space:]]*build:/,/^[[:space:]]*args:/d' "\${COMPOSE_FILE_NAME}"
    sed -i '/^[[:space:]]*PENTAHO_VERSION:/d' "\${COMPOSE_FILE_NAME}"
    echo "✅ Removed build sections"
else
    echo "ℹ️  No build sections found"
fi

# Fix directory permissions for container user (pentaho uid=5000)
echo ""
echo "🔧 Fixing directory permissions for container user..."
sudo chown -R 5000:5000 logs/ softwareOverride/ config/
sudo chmod -R 775 logs/ softwareOverride/ config/


# Fix CPU and memory limits
echo ""
echo "🔧 Adjusting container resource limits from config..."
# Pentaho server container limits
sed -i "s|cpus: '3'|cpus: '\${PENTAHO_CONTAINER_CPU_LIMIT}'|g" "\${COMPOSE_FILE_NAME}" 2>/dev/null || true
sed -i "s|memory: 5g|memory: \${PENTAHO_CONTAINER_MEMORY_LIMIT}|g" "\${COMPOSE_FILE_NAME}" 2>/dev/null || true

# Database container limits (apply to postgres/mysql service)
# Find and update the database service section (it comes after pentaho-server in compose file)
# We'll use a more targeted approach to avoid modifying pentaho settings
sed -i "/^  ${DB_TYPE}:/,/^  [a-z]/ {
    s|cpus: '[0-9.]*'|cpus: '\${DATABASE_CONTAINER_CPU_LIMIT}'|g;
    s|memory: [0-9.]*[gGmM][bB]*|memory: \${DATABASE_CONTAINER_MEMORY_LIMIT}|g;
}" "\${COMPOSE_FILE_NAME}" 2>/dev/null || echo "  Note: Database resource limits may need manual adjustment"

echo "✅ Resource limits configured:"
echo "   Pentaho: \${PENTAHO_CONTAINER_CPU_LIMIT} CPUs, \${PENTAHO_CONTAINER_MEMORY_LIMIT}"
echo "   Database: \${DATABASE_CONTAINER_CPU_LIMIT} CPUs, \${DATABASE_CONTAINER_MEMORY_LIMIT}"

echo ""
echo "✅ Deployment complete!"
docker compose -f "\${COMPOSE_FILE_NAME}" ps || true
echo ""
echo "🚀 Starting services..."
docker compose -f "\${COMPOSE_FILE_NAME}" down 2>/dev/null || true
docker compose -f "\${COMPOSE_FILE_NAME}" up -d

echo ""
echo "✅ Deployment complete!"
docker compose -f "\${COMPOSE_FILE_NAME}" ps

if [ "${ENVIRONMENT}" = "ops-console" ]; then
    echo ""
    echo "🔧 Ops-console mode: redirecting port 80 root to Ops Console (:8000)..."
    PENTAHO_CID=\$(docker compose -f "\${COMPOSE_FILE_NAME}" ps -q pentaho-server | head -1)
    if [ -n "\${PENTAHO_CID}" ]; then
        docker exec "\${PENTAHO_CID}" sh -lc 'cat > /opt/pentaho/pentaho-server/tomcat/webapps/ROOT/index.jsp << "EOF"
<%
String scheme = request.getScheme();
String host = request.getServerName();
String target = scheme + "://" + host + ":8000/";
response.sendRedirect(target);
%>
EOF'
        echo "✅ ROOT redirect patched: http://<host>/ -> http://<host>:8000/"
        echo "   Pentaho remains available at http://<host>/pentaho"
    else
        echo "⚠️  Could not find pentaho-server container to patch ROOT redirect"
    fi
fi
DEPLOY_SCRIPT

# Execute deployment
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
    "chmod +x /home/${SSH_USER}/pentaho/deploy.sh && /home/${SSH_USER}/pentaho/deploy.sh"

echo ""
echo "🎉 Deployment Complete!"
echo ""
echo "🌐 Access: http://${SSH_IP}/pentaho"
echo "👤 Login: admin/password"
echo ""
echo "📦 Next Steps:"
echo "   Install all plugins: ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
echo "   Install single plugin: ./21-deploy-plugin.sh ${ENV_FILE_NAME} <plugin-name>"
echo "   Monitor resources: ./97-monitor-resources.sh ${ENV_FILE_NAME}"
echo ""