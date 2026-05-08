#!/bin/bash

# Pentaho Data Catalog (PDC) Deployment Script
# Downloads PDC artifacts, extracts deployment bundle, and deploys with Docker Compose
# Reference: https://docs.pentaho.com/pdc-10.2-install/install-pentaho-data-catalog/install-data-catalog

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pdc-10.2.10.env"
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
    echo "❌ Error: Runtime state not found. Run 02-create-ec2.sh first"
    exit 1
fi

source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

# Validate required PDC variables
if [ -z "${PDC_VERSION:-}" ]; then
    echo "❌ Error: PDC_VERSION not set in ${ENV_FILE_NAME}"
    exit 1
fi
if [ -z "${PDC_ARTIFACT:-}" ]; then
    echo "❌ Error: PDC_ARTIFACT not set in ${ENV_FILE_NAME}"
    echo "   Browse JFrog release-v${PDC_VERSION}/ and set PDC_ARTIFACT to the *-compose.tgz filename"
    exit 1
fi

echo "🚀 Pentaho Data Catalog (PDC) Deployment"
echo "=========================================="
echo "📋 Environment: ${ENVIRONMENT}"
echo "📋 PDC Version: ${PDC_VERSION}"
echo "📋 Artifact: ${PDC_ARTIFACT}"
echo "📋 EC2 Instance: ${SSH_IP}"
echo ""

echo "🔍 Testing SSH connection..."
if ! ssh -i "${KEY_PATH}" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} echo "Connected" 2>/dev/null; then
    echo "❌ Cannot connect to EC2 instance"
    exit 1
fi
echo "✅ SSH connection verified"
echo ""

# ── Step 1: Download PDC artifacts to EC2 ────────────────────────────────────

echo "📥 Step 1: Downloading PDC artifacts to EC2"
echo "============================================="
echo ""

# Construct artifact URL
PDC_JFROG_BASE="${PDC_JFROG_BASE_URL:-https://one.hitachivantara.com/artifactory/pdc-generic-dev/pentaho/pdc-docker-deployment}"
PDC_RELEASE_DIR="release-v${PDC_VERSION}"
PDC_COMPOSE_FILE="${PDC_ARTIFACT}"

ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/pentaho/download-pdc.sh" << DOWNLOAD_SCRIPT
#!/bin/bash
set -e
cd /home/${SSH_USER}/pentaho

JFROG_TOKEN="${JFROG_TOKEN}"
PDC_JFROG_BASE="${PDC_JFROG_BASE}"
PDC_RELEASE_DIR="${PDC_RELEASE_DIR}"
PDC_COMPOSE_FILE="${PDC_COMPOSE_FILE}"

download_pdc_file() {
    local filename=\$1
    local url="\${PDC_JFROG_BASE}/\${PDC_RELEASE_DIR}/\${filename}"
    local min_size=1048576  # 1MB minimum
    
    if [ -f "\${filename}" ]; then
        local filesize=\$(stat -c%s "\${filename}" 2>/dev/null || stat -f%z "\${filename}" 2>/dev/null)
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
                if [ \$(( pct / 10 )) -gt \$(( last_pct / 10 )) ] 2>/dev/null; then
                    local cur_mb=\$(( cur / 1048576 ))
                    echo "   \${pct}%  (\${cur_mb}MB / \${total_mb}MB)"
                    last_pct=\${pct}
                fi
            fi
            sleep 2
        done
    else
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
        local filesize=\$(stat -c%s "\${filename}" 2>/dev/null || stat -f%z "\${filename}" 2>/dev/null)
        local human_size=\$(numfmt --to=iec \${filesize} 2>/dev/null || echo "\${filesize} bytes")
        
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

download_pdc_file "\${PDC_COMPOSE_FILE}"
echo ""
echo "✅ PDC downloads complete"
ls -lh \${PDC_COMPOSE_FILE} 2>/dev/null || true
DOWNLOAD_SCRIPT

ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
    "chmod +x /home/${SSH_USER}/pentaho/download-pdc.sh && /home/${SSH_USER}/pentaho/download-pdc.sh"

echo ""
echo "✅ Download complete!"
echo ""

# ── Step 2: Deploy PDC ──────────────────────────────────────────────────────

echo "🚀 Step 2: Deploying PDC"
echo "========================="
echo ""

ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/pentaho/deploy-pdc.sh" << DEPLOY_SCRIPT
#!/bin/bash
set -e
cd /home/${SSH_USER}/pentaho

PDC_VERSION="${PDC_VERSION}"
PDC_COMPOSE_FILE="${PDC_COMPOSE_FILE}"
PDC_LICENSE_URL="${PDC_LICENSE_URL}"
EMAIL_DOMAINS='${EMAIL_DOMAINS:-["hv.com", "hitachivantara.com"]}'
JFROG_USER="${JFROG_USER}"
JFROG_TOKEN="${JFROG_TOKEN}"
SSH_IP="${SSH_IP}"

echo "📦 Extracting PDC deployment bundle..."
sudo rm -rf /opt/pentaho/pdc-docker-deployment
sudo mkdir -p /opt/pentaho
sudo tar -xvf "\${PDC_COMPOSE_FILE}" -C /opt 2>&1 | tail -5
echo ""

if [ ! -d /opt/pentaho/pdc-docker-deployment ]; then
    echo "❌ Extraction failed: /opt/pentaho/pdc-docker-deployment not found"
    echo "📂 Contents of /opt/pentaho:"
    ls -la /opt/pentaho/ 2>/dev/null || echo "   (empty)"
    exit 1
fi
echo "✅ Extracted to /opt/pentaho/pdc-docker-deployment"

echo ""
echo "🔧 Applying MongoDB UID compatibility fix..."
if [ -f /opt/pentaho/pdc-docker-deployment/vendor/docker-compose.yml ]; then
    sudo sed -i 's|chown -R 101:0|chown -R 1000:0|g' /opt/pentaho/pdc-docker-deployment/vendor/docker-compose.yml
    echo "✅ MongoDB UID fix applied (101 → 1000)"
else
    echo "⚠️  vendor/docker-compose.yml not found, skipping UID fix"
fi

echo ""
echo "⚙️  Configuring PDC..."
cd /opt/pentaho/pdc-docker-deployment

# Ensure conf directory exists (fresh extraction may not have it)
sudo mkdir -p conf

# Run pdc.sh to initialize (non-interactive: set GLOBAL_SERVER_HOST_NAME first)
if [ -f conf/.env ]; then
    echo "📋 Backing up existing conf/.env"
    cp conf/.env conf/.env.backup
fi

# Set the server hostname to the instance IP
if [ -f conf/.env ]; then
    if grep -q "GLOBAL_SERVER_HOST_NAME" conf/.env; then
        sudo sed -i "s|GLOBAL_SERVER_HOST_NAME=.*|GLOBAL_SERVER_HOST_NAME=\${SSH_IP}|g" conf/.env
    else
        echo "GLOBAL_SERVER_HOST_NAME=\${SSH_IP}" | sudo tee -a conf/.env > /dev/null
    fi
else
    echo "GLOBAL_SERVER_HOST_NAME=\${SSH_IP}" | sudo tee conf/.env > /dev/null
fi

# Configure licensing
if [ -n "\${PDC_LICENSE_URL}" ]; then
    if grep -q "LICENSING_SERVER_URL" conf/.env; then
        sudo sed -i "s|LICENSING_SERVER_URL=.*|LICENSING_SERVER_URL=\${PDC_LICENSE_URL}|g" conf/.env
    else
        echo "LICENSING_SERVER_URL=\${PDC_LICENSE_URL}" | sudo tee -a conf/.env > /dev/null
    fi
    if grep -q "^PDI_LICENSE_URL=" conf/.env; then
        sudo sed -i "s|^PDI_LICENSE_URL=.*|PDI_LICENSE_URL=\${PDC_LICENSE_URL}|g" conf/.env
    else
        echo "PDI_LICENSE_URL=\${PDC_LICENSE_URL}" | sudo tee -a conf/.env > /dev/null
    fi
    echo "✅ License URL configured"
fi

# Keep PDI tray licensing in sync with global licensing URL for 10.2.11+ bundles.
_lic_url="$(grep -E '^LICENSING_SERVER_URL=' conf/.env | tail -1 | cut -d= -f2-)"
_pdi_lic_url="$(grep -E '^PDI_LICENSE_URL=' conf/.env | tail -1 | cut -d= -f2-)"
if [ -n "${_lic_url}" ] && [ -z "${_pdi_lic_url}" ]; then
    echo "PDI_LICENSE_URL=${_lic_url}" | sudo tee -a conf/.env > /dev/null
    echo "✅ Added PDI_LICENSE_URL from LICENSING_SERVER_URL"
fi

# Configure email domains
if grep -q "EMAIL_DOMAINS" conf/.env; then
    sudo sed -i "s|EMAIL_DOMAINS=.*|EMAIL_DOMAINS='\${EMAIL_DOMAINS}'|g" conf/.env
else
    echo "EMAIL_DOMAINS='\${EMAIL_DOMAINS}'" | sudo tee -a conf/.env > /dev/null
fi

# Generate PDC_DATA_ENCRYPTION_KEY if not already set
if ! grep -q "PDC_DATA_ENCRYPTION_KEY" conf/.env; then
    PDC_ENC_KEY=\$(openssl rand -base64 32)
    echo "PDC_DATA_ENCRYPTION_KEY=\${PDC_ENC_KEY}" | sudo tee -a conf/.env > /dev/null
    echo "✅ Generated PDC_DATA_ENCRYPTION_KEY"
else
    echo "✅ PDC_DATA_ENCRYPTION_KEY already set"
fi

echo ""
echo "📋 PDC conf/.env (relevant settings):"
grep -E "GLOBAL_SERVER_HOST_NAME|LICENSING_SERVER_URL|PDI_LICENSE_URL|EMAIL_DOMAINS|PDC_DATA_ENCRYPTION_KEY" conf/.env || true

echo ""
echo "� Ensuring docker-compose compatibility..."
# PDC's pdc.sh expects standalone 'docker-compose' (v1), but modern Docker only
# ships 'docker compose' (v2 plugin). Create a shim if needed.
if ! docker-compose version &>/dev/null; then
    echo "   docker-compose not found — creating shim to 'docker compose'"
    sudo tee /usr/local/bin/docker-compose > /dev/null << 'SHIM'
#!/bin/sh
exec docker compose "\$@"
SHIM
    sudo chmod +x /usr/local/bin/docker-compose
    echo "   ✅ Shim created at /usr/local/bin/docker-compose"
else
    echo "   ✅ docker-compose already available"
fi

echo ""
echo "🔑 Authenticating with JFrog Docker registry..."
echo "\${JFROG_TOKEN}" | sudo docker login hitachi.jfrog.io --username "\${JFROG_USER}" --password-stdin
echo "✅ Docker registry authenticated"

echo ""
echo "🚀 Starting PDC services..."
if [ -f pdc.sh ]; then
    sudo chmod +x pdc.sh
    sudo bash pdc.sh up 2>&1
else
    echo "⚠️  pdc.sh not found, trying docker compose directly..."
    sudo docker compose up -d 2>&1
fi

echo ""
echo "✅ PDC deployment complete!"
echo ""
echo "📋 Container status:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || sudo docker ps
DEPLOY_SCRIPT

ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
    "chmod +x /home/${SSH_USER}/pentaho/deploy-pdc.sh && /home/${SSH_USER}/pentaho/deploy-pdc.sh"

echo ""
echo "🎉 PDC Deployment Complete!"
echo ""
echo "🌐 Access: https://${SSH_IP}"
echo "   (Self-signed certificate — browser will show a security warning)"
echo ""
echo "📦 Next Steps:"
echo "   Monitor resources: ./97-monitor-resources.sh ${ENV_FILE_NAME}"
echo "   Teardown: ./99-teardown.sh ${ENV_FILE_NAME}"
echo ""
