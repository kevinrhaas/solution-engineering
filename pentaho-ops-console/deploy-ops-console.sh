#!/bin/bash
# deploy-ops-console.sh
# Deploy pentaho-ops-console to an EC2 instance created by pentaho-11-docker-deploy
#
# Usage: ./deploy-ops-console.sh <env-file>
# Example: ./deploy-ops-console.sh pentaho-ops-console.env
#
# This script:
#   1. Builds the React UI locally (npm run build)
#   2. Packages the project (api/ + ui/dist/ + requirements.txt) and deploy scripts
#   3. SCPs them to the EC2 instance and extracts into the workspace
#   4. Installs Node.js, Python deps, and sets up the environment
#   5. Initializes a git repo with HTTPS remote for self-updates via the web UI
#   6. Starts the ops-console service via systemd on port 8000

set -e

# ── Configuration ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_DIR="${WORKSPACE_ROOT}/pentaho-11-docker-deploy"
OPS_DIR="${SCRIPT_DIR}"

ENV_FILE_NAME="$(basename "${1:-pentaho-ops-console.env}")"

if [ -z "$1" ]; then
    echo "❌ Environment file parameter required"
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-ops-console.env"
    exit 1
fi

# Source .env
if [ ! -f "${DEPLOY_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${DEPLOY_DIR}/${ENV_FILE_NAME}"
    exit 1
fi
source "${DEPLOY_DIR}/${ENV_FILE_NAME}"

# Source runtime state to get the IP
STATE_FILE_NAME="${ENV_FILE_NAME%.env}-runtime.state"
if [ ! -f "${DEPLOY_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ Error: Runtime state file not found: ${STATE_FILE_NAME}"
    echo "   Run 02-create-ec2.sh first to create the instance."
    exit 1
fi
source "${DEPLOY_DIR}/${STATE_FILE_NAME}"

# Determine target IP
TARGET_IP="${PUBLIC_IP:-${PRIVATE_IP}}"
if [ -z "${TARGET_IP}" ]; then
    echo "❌ Error: No IP address found in state file"
    exit 1
fi

echo "🚀 Deploying Pentaho Ops Console"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Target: ${SSH_USER}@${TARGET_IP}"
echo "Key:    ${KEY_PATH}"
echo ""

SSH_OPTS="-i ${KEY_PATH} -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# ── Step 1: Build React UI ──────────────────────────────────────────────────

echo "📦 Step 1/5: Building React UI..."
cd "${OPS_DIR}/ui"
npm run build 2>&1 | tail -3
echo "✅ UI built"
echo ""

# ── Step 2: Package project ─────────────────────────────────────────────────

echo "📦 Step 2/5: Packaging project..."
TARBALL="/tmp/pentaho-ops-console.tar.gz"
SCRIPTS_TARBALL="/tmp/pentaho-ops-scripts.tar.gz"

cd "${OPS_DIR}"
tar czf "${TARBALL}" \
    --exclude='ui/node_modules' \
    --exclude='ui/src' \
    --exclude='ui/.gitignore' \
    --exclude='ui/tsconfig*' \
    --exclude='ui/eslint*' \
    --exclude='ui/vite.config.ts' \
    --exclude='ui/public' \
    --exclude='ui/README.md' \
    --exclude='api/__pycache__' \
    --exclude='api/routes/__pycache__' \
    api/ \
    ui/ \
    requirements.txt

echo "✅ App package: $(du -h ${TARBALL} | awk '{print $1}')"

# Package deploy scripts + migration scripts for the remote server
cd "${WORKSPACE_ROOT}"
tar czf "${SCRIPTS_TARBALL}" \
    --exclude='pentaho-11-docker-deploy/downloads' \
    --exclude='pentaho-11-docker-deploy/generatedFiles' \
    --exclude='pentaho-11-docker-deploy/softwareOverride' \
    --exclude='pentaho-11-docker-deploy/archive' \
    pentaho-11-docker-deploy/*.sh \
    pentaho-11-docker-deploy/*.env \
    pentaho-11-docker-deploy/*-runtime.state \
    pdc-analysis/utility/ \
    pdc-analysis/content/ \
    pdc-analysis/analyzer/ \
    2>/dev/null || true

echo "✅ Scripts package: $(du -h ${SCRIPTS_TARBALL} | awk '{print $1}')"
echo ""

# ── Step 3: Upload to EC2 ───────────────────────────────────────────────────

echo "📤 Step 3/5: Uploading to ${TARGET_IP}..."

scp ${SSH_OPTS} "${TARBALL}" "${SSH_USER}@${TARGET_IP}:/tmp/pentaho-ops-console.tar.gz"
scp ${SSH_OPTS} "${SCRIPTS_TARBALL}" "${SSH_USER}@${TARGET_IP}:/tmp/pentaho-ops-scripts.tar.gz"
echo "✅ Upload complete"
echo ""

# ── Step 4: Install and set up on remote ─────────────────────────────────────

echo "🔧 Step 4/5: Installing on remote server..."

ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" << 'REMOTE_SCRIPT'
set -e

echo "--- Installing system dependencies ---"
sudo apt-get update -qq
sudo apt-get install -y -qq python3-pip python3-venv unzip jq git > /dev/null

# Install Node.js 20 LTS if not present (needed for self-update npm build)
if ! command -v node &>/dev/null; then
    echo "--- Installing Node.js 20 LTS ---"
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - > /dev/null 2>&1
    sudo apt-get install -y -qq nodejs > /dev/null
    echo "Node.js installed: $(node -v)"
else
    echo "Node.js already installed: $(node -v)"
fi

# Install AWS CLI v2 if not present
if ! command -v aws &>/dev/null; then
    echo "--- Installing AWS CLI v2 ---"
    cd /tmp
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    echo "AWS CLI installed: $(aws --version)"
else
    echo "AWS CLI already installed: $(aws --version)"
fi

echo "--- Setting up workspace ---"
WORKSPACE="/home/ubuntu/pentaho-workspace"
OPS_HOME="${WORKSPACE}/pentaho-ops-console"

# Extract app into workspace/pentaho-ops-console/
rm -rf "${OPS_HOME}"
mkdir -p "${OPS_HOME}"
cd "${OPS_HOME}"
tar xzf /tmp/pentaho-ops-console.tar.gz
rm /tmp/pentaho-ops-console.tar.gz

# Extract scripts into workspace/
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"
tar xzf /tmp/pentaho-ops-scripts.tar.gz
rm /tmp/pentaho-ops-scripts.tar.gz

echo "--- Installing npm dependencies (for self-update builds) ---"
cd "${OPS_HOME}/ui"
npm ci --silent 2>&1 | tail -3

echo "--- Creating Python virtual environment ---"
cd "${OPS_HOME}"
python3 -m venv venv
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

echo "--- Initializing git repo for self-updates ---"
cd "${WORKSPACE}"
if [ ! -d .git ]; then
    git init -q
    git remote add origin https://github.com/pentaho/solution-engineering.git
    echo "Git repo initialized (HTTPS)"
else
    # Ensure remote uses HTTPS (may have been SSH before)
    git remote set-url origin https://github.com/pentaho/solution-engineering.git 2>/dev/null || true
    echo "Git repo already initialized"
fi
# Configure safe directory
git config --global --add safe.directory "${WORKSPACE}"

# Configure git credential store so PAT persists
git config credential.helper store

# If a GitHub token is already stored, test connectivity
echo "--- Testing GitHub connectivity ---"
if git fetch --depth 1 origin main 2>/dev/null; then
    git branch -f main FETCH_HEAD 2>/dev/null || true
    echo "✅ Git fetch succeeded — self-update is ready"
else
    echo "⚠️  Git fetch failed — configure a GitHub Personal Access Token in the Config page"
fi
REMOTE_SCRIPT

# ── Push credentials ────────────────────────────────────────────────────────

echo ""
echo "🔑 Pushing credentials..."

# Push SSH key to the remote server so it can SSH into other instances
if [ -f "${KEY_PATH}" ]; then
    ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    scp ${SSH_OPTS} "${KEY_PATH}" "${SSH_USER}@${TARGET_IP}:~/.ssh/$(basename ${KEY_PATH})"
    ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" "chmod 600 ~/.ssh/$(basename ${KEY_PATH})"
    echo "✅ SSH key pushed"
else
    echo "⚠️  SSH key not found at ${KEY_PATH}, skipping push"
fi

# Push local AWS credentials to the remote server
LOCAL_AWS_CREDS="$HOME/.aws/credentials"
if [ -f "${LOCAL_AWS_CREDS}" ]; then
    ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" "mkdir -p ~/.aws && chmod 700 ~/.aws"
    scp ${SSH_OPTS} "${LOCAL_AWS_CREDS}" "${SSH_USER}@${TARGET_IP}:~/.aws/credentials"
    ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" "chmod 600 ~/.aws/credentials"
    if [ -f "$HOME/.aws/config" ]; then
        scp ${SSH_OPTS} "$HOME/.aws/config" "${SSH_USER}@${TARGET_IP}:~/.aws/config"
        ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" "chmod 600 ~/.aws/config"
    fi
    echo "✅ AWS credentials pushed"
else
    echo "⚠️  AWS credentials not found at ${LOCAL_AWS_CREDS}, skipping push"
fi

# ── Step 5: Create systemd service and start ─────────────────────────────────

echo ""
echo "⚙️  Step 5/5: Starting service..."

ssh ${SSH_OPTS} "${SSH_USER}@${TARGET_IP}" << 'REMOTE_SCRIPT2'
set -e

echo "--- Creating systemd service ---"
sudo tee /etc/systemd/system/pentaho-ops-console.service > /dev/null << SERVICEEOF
[Unit]
Description=Pentaho Ops Console
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/pentaho-workspace/pentaho-ops-console
ExecStart=/home/ubuntu/pentaho-workspace/pentaho-ops-console/venv/bin/uvicorn api.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
Environment=PATH=/home/ubuntu/pentaho-workspace/pentaho-ops-console/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=OPS_WORKSPACE_ROOT=/home/ubuntu/pentaho-workspace
Environment=OPS_DEPLOY_SCRIPTS_DIR=/home/ubuntu/pentaho-workspace/pentaho-11-docker-deploy
Environment=OPS_MIGRATE_SCRIPTS_DIR=/home/ubuntu/pentaho-workspace/pdc-analysis/utility
Environment=OPS_DATA_DIR=/home/ubuntu/.local/share/pentaho-ops-console

[Install]
WantedBy=multi-user.target
SERVICEEOF

echo "--- Starting service ---"
sudo systemctl daemon-reload
sudo systemctl enable pentaho-ops-console
sudo systemctl restart pentaho-ops-console

sleep 2

if sudo systemctl is-active --quiet pentaho-ops-console; then
    echo "✅ pentaho-ops-console is running"
else
    echo "❌ Service failed to start. Checking logs:"
    sudo journalctl -u pentaho-ops-console --no-pager -n 20
    exit 1
fi
REMOTE_SCRIPT2

# Retrieve and display info
echo ""

echo "🎉 Pentaho Ops Console deployed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  URL:  http://${TARGET_IP}:8000"
echo "  API:  http://${TARGET_IP}:8000/api/health"
echo "  Logs: ssh ${SSH_OPTS} ${SSH_USER}@${TARGET_IP} 'journalctl -u pentaho-ops-console -f'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 To enable self-updates from the web UI, go to Config → App Sync"
echo "   and enter a GitHub Personal Access Token (fine-grained, read-only Contents)."
echo "   Generate one at: https://github.com/settings/tokens?type=beta"

# Cleanup
rm -f "${TARBALL}" "${SCRIPTS_TARBALL}"
