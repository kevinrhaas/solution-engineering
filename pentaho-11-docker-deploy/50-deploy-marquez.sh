#!/bin/bash
# 50-deploy-marquez.sh
# Deploy Marquez OpenLineage server on an EC2 instance via Docker Compose
#
# Prerequisites: run 02-create-ec2.sh marquez.env first to provision the instance.
#
# Usage: ./50-deploy-marquez.sh marquez.env

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 marquez.env"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Config file not found: ${ENV_FILE_NAME}"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"

# Resolve state file (newest match for this env profile)
if [ -n "${STATE_FILE:-}" ]; then
    STATE_FILE_NAME="$(basename "$STATE_FILE")"
else
    _found=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
    STATE_FILE_NAME="${_found:+$(basename "$_found")}"
fi

if [ -z "${STATE_FILE_NAME}" ] || [ ! -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ No runtime state found. Run: ./02-create-ec2.sh ${ENV_FILE_NAME} first."
    exit 1
fi

source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

echo "🚀 Marquez OpenLineage Deployment"
echo "=================================="
echo "📋 Environment: ${ENVIRONMENT}"
echo "📋 EC2 Instance: ${SSH_IP}"
echo "📋 Marquez API port: ${MARQUEZ_API_PORT:-5000}"
echo "📋 Marquez Web UI port: ${MARQUEZ_WEB_PORT:-3000}"
echo ""

echo "🔍 Testing SSH connection..."
if ! ssh -i "${KEY_PATH}" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} echo "Connected" 2>/dev/null; then
    echo "❌ Cannot connect to ${SSH_IP}"
    echo "   Make sure the EC2 is running and user-data has finished (~3 min after creation)."
    exit 1
fi
echo "✅ SSH connection verified"
echo ""

echo "📦 Step 1: Installing Docker Compose (if needed) and pulling Marquez images"
echo "============================================================================="

ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "cat > /home/${SSH_USER}/deploy-marquez.sh" << REMOTE_SCRIPT
#!/bin/bash
set -e

MARQUEZ_API_PORT="${MARQUEZ_API_PORT:-5000}"
MARQUEZ_ADMIN_PORT="${MARQUEZ_ADMIN_PORT:-5001}"
MARQUEZ_WEB_PORT="${MARQUEZ_WEB_PORT:-3000}"
MARQUEZ_DB_USER="${MARQUEZ_DB_USER:-marquez}"
MARQUEZ_DB_PASSWORD="${MARQUEZ_DB_PASSWORD:-marquez}"
MARQUEZ_DB_NAME="${MARQUEZ_DB_NAME:-marquez}"

echo "🐳 Checking Docker..."
docker --version
docker compose version 2>/dev/null || docker-compose --version

# Create deployment directory
mkdir -p /home/${SSH_USER}/marquez
cd /home/${SSH_USER}/marquez

echo "📝 Writing docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE_EOF'
version: "3.7"

services:
  marquez:
    image: marquezproject/marquez:latest
    container_name: marquez-api
    environment:
      - MARQUEZ_CONFIG=/usr/src/app/marquez.yml
    ports:
      - "\${MARQUEZ_API_PORT}:5000"
      - "\${MARQUEZ_ADMIN_PORT}:5001"
    volumes:
      - ./marquez.yml:/usr/src/app/marquez.yml:ro
    depends_on:
      marquez_db:
        condition: service_healthy
    restart: unless-stopped

  marquez-web:
    image: marquezproject/marquez-web:latest
    container_name: marquez-web
    environment:
      - MARQUEZ_HOST=marquez
      - MARQUEZ_PORT=5000
      - WEB_PORT=3000
    ports:
      - "\${MARQUEZ_WEB_PORT}:3000"
    depends_on:
      - marquez
    restart: unless-stopped

  marquez_db:
    image: postgres:14
    container_name: marquez-db
    environment:
      - POSTGRES_USER=\${MARQUEZ_DB_USER}
      - POSTGRES_PASSWORD=\${MARQUEZ_DB_PASSWORD}
      - POSTGRES_DB=\${MARQUEZ_DB_NAME}
    volumes:
      - marquez_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${MARQUEZ_DB_USER} -d \${MARQUEZ_DB_NAME}"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

volumes:
  marquez_db_data:
COMPOSE_EOF

echo "📝 Writing marquez.yml..."
cat > marquez.yml << CONF_EOF
server:
  applicationConnectors:
    - type: http
      port: 5000
  adminConnectors:
    - type: http
      port: 5001

db:
  driverClass: org.postgresql.Driver
  url: jdbc:postgresql://marquez_db:5432/\${MARQUEZ_DB_NAME}
  user: \${MARQUEZ_DB_USER}
  password: \${MARQUEZ_DB_PASSWORD}

migrateOnStartup: true

tags: []
CONF_EOF

echo "📝 Writing .env for Docker Compose variable substitution..."
cat > .env << ENV_EOF
MARQUEZ_API_PORT=\${MARQUEZ_API_PORT}
MARQUEZ_ADMIN_PORT=\${MARQUEZ_ADMIN_PORT}
MARQUEZ_WEB_PORT=\${MARQUEZ_WEB_PORT}
MARQUEZ_DB_USER=\${MARQUEZ_DB_USER}
MARQUEZ_DB_PASSWORD=\${MARQUEZ_DB_PASSWORD}
MARQUEZ_DB_NAME=\${MARQUEZ_DB_NAME}
ENV_EOF

echo "📥 Pulling Marquez images..."
docker compose pull

echo "🚀 Starting Marquez..."
docker compose down 2>/dev/null || true
docker compose up -d

echo ""
echo "⏳ Waiting for Marquez API to be healthy (up to 60s)..."
for i in \$(seq 1 12); do
    if curl -sf http://localhost:\${MARQUEZ_API_PORT}/api/v1/namespaces > /dev/null 2>&1; then
        echo "✅ Marquez API is up!"
        break
    fi
    echo "   Attempt \${i}/12 — waiting 5s..."
    sleep 5
done

echo ""
echo "📋 Container status:"
docker compose ps

echo ""
echo "✅ Marquez deployment complete"
echo "   API:    http://\$(hostname -I | awk '{print \$1}'):\${MARQUEZ_API_PORT}"
echo "   Web UI: http://\$(hostname -I | awk '{print \$1}'):\${MARQUEZ_WEB_PORT}"
REMOTE_SCRIPT

echo "🚀 Step 2: Running deployment on EC2..."
echo "========================================"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
    "chmod +x /home/${SSH_USER}/deploy-marquez.sh && /home/${SSH_USER}/deploy-marquez.sh"

echo ""
echo "🎉 Marquez Deployment Complete!"
echo "================================"
echo ""
echo "  API (OpenLineage):  http://${SSH_IP}:${MARQUEZ_API_PORT:-5000}"
echo "  Web UI:             http://${SSH_IP}:${MARQUEZ_WEB_PORT:-3000}"
echo "  Health check:       http://${SSH_IP}:${MARQUEZ_ADMIN_PORT:-5001}/healthcheck"
echo ""
echo "📋 Configure Pentaho OpenLineage plugin (~/.kettle/openlineageConfig.yml):"
echo "   url: \"http://${SSH_IP}:${MARQUEZ_API_PORT:-5000}\""
echo "   endpoint: \"/api/v1/lineage\""
echo ""
echo "📋 Next steps:"
echo "   Test connectivity:  ./51-test-marquez.sh ${ENV_FILE_NAME}"
echo "   SSH into server:    ./96-ssh-into-instance.sh ${ENV_FILE_NAME}"
echo ""

# Update state file with Marquez info
if [ -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    if ! grep -q '^MARQUEZ_URL=' "${SCRIPT_DIR}/${STATE_FILE_NAME}"; then
        echo "" >> "${SCRIPT_DIR}/${STATE_FILE_NAME}"
        echo "# Marquez" >> "${SCRIPT_DIR}/${STATE_FILE_NAME}"
        echo "MARQUEZ_URL=http://${SSH_IP}:${MARQUEZ_API_PORT:-5000}" >> "${SCRIPT_DIR}/${STATE_FILE_NAME}"
        echo "MARQUEZ_WEB_URL=http://${SSH_IP}:${MARQUEZ_WEB_PORT:-3000}" >> "${SCRIPT_DIR}/${STATE_FILE_NAME}"
    fi
fi
