#!/bin/bash

# full-deployment.sh
# Complete Pentaho deployment from start to finish
# This script orchestrates all four deployment steps with error handling and logging

set -e

# Configuration
ENVIRONMENT=${1}

# Validate environment parameter
if [ -z "$ENVIRONMENT" ]; then
    echo "❌ Environment parameter required"
    echo "Usage: $0 [environment-name]"
    echo "Example: $0 dev"
    echo "Example: $0 test"
    echo "Example: $0 monkey"
    exit 1
fi

LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/full-deployment-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p "${LOG_DIR}"

# Logging function
log() {
    echo -e "$1" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local exit_code=$?
    log "${RED}❌ Deployment failed at step: $1${NC}"
    log "${RED}   Exit code: ${exit_code}${NC}"
    log "${RED}   Check log file: ${LOG_FILE}${NC}"
    exit ${exit_code}
}

log "${BLUE}🚀 Starting Full Pentaho Deployment - ${ENVIRONMENT}${NC}"
log "${BLUE}===============================================${NC}"
log "${BLUE}📝 Log file: ${LOG_FILE}${NC}"
log ""

# Check if environment file exists
if [ ! -f "pentaho-deployment-${ENVIRONMENT}.env" ]; then
    log "${RED}❌ Environment file not found: pentaho-deployment-${ENVIRONMENT}.env${NC}"
    log "${YELLOW}Available environments:${NC}"
    ls -1 pentaho-deployment-*.env 2>/dev/null | sed 's/pentaho-deployment-//; s/.env//' | sed 's/^/   /' || log "   None found"
    exit 1
fi

log "${GREEN}✅ Using environment: ${ENVIRONMENT}${NC}"
log ""

# Confirmation prompt
log "${YELLOW}This will deploy Pentaho with the following steps:${NC}"
log "  1️⃣  Create EC2 instance"
log "  2️⃣  Download and install Pentaho files"
log "  3️⃣  Build Docker containers"
log "  4️⃣  Deploy and start containers"
log ""
read -p "Continue with deployment? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log "${YELLOW}❌ Deployment cancelled${NC}"
    exit 0
fi

# Step 1: Create EC2 Instance
log "${BLUE}📍 Step 1: Creating EC2 Instance${NC}"
log "================================"
./01-create-pentaho-ec2.sh ${ENVIRONMENT} 2>&1 | tee -a "${LOG_FILE}"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    handle_error "Step 1 - EC2 Creation"
fi
log "${GREEN}✅ Step 1 completed successfully${NC}"
log ""

# Wait for EC2 instance initialization to complete
log "${YELLOW}⏳ Waiting for EC2 instance initialization...${NC}"
log "   Instance user-data script is installing Docker, mounting EBS volume, etc."
log "   This typically takes 2-3 minutes..."
log ""

for i in {180..1}; do
    printf "\r   Waiting: %d seconds remaining..." $i
    sleep 1
done
printf "\n"

log "${GREEN}✅ EC2 initialization wait completed${NC}"
log ""

# Step 2: Download Pentaho Files
log "${BLUE}📦 Step 2: Downloading Pentaho Files${NC}"
log "===================================="
./02-download-pentaho-files.sh ${ENVIRONMENT} 2>&1 | tee -a "${LOG_FILE}"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    handle_error "Step 2 - File Download"
fi
log "${GREEN}✅ Step 2 completed successfully${NC}"
log ""

# Step 3: Build Containers
log "${BLUE}🔨 Step 3: Building Pentaho Containers${NC}"
log "======================================"
./03-build-pentaho-containers.sh ${ENVIRONMENT} full 2>&1 | tee -a "${LOG_FILE}"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    handle_error "Step 3 - Container Build"
fi
log "${GREEN}✅ Step 3 completed successfully${NC}"
log ""

# Step 4: Deploy Containers
log "${BLUE}🚀 Step 4: Deploying Pentaho Containers${NC}"
log "======================================="
./04-deploy-pentaho.sh ${ENVIRONMENT} 2>&1 | tee -a "${LOG_FILE}"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    handle_error "Step 4 - Container Deployment"
fi
log "${GREEN}✅ Step 4 completed successfully${NC}"
log ""

# Success summary
log "${GREEN}🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉${NC}"
log "${GREEN}=====================================${NC}"
log ""

# Extract connection info from runtime state
RUNTIME_STATE="pentaho-deployment-${ENVIRONMENT}-runtime.state"
if [ -f "${RUNTIME_STATE}" ]; then
    source "${RUNTIME_STATE}"
    log "${BLUE}📍 Connection Information:${NC}"
    log "   Environment: ${ENVIRONMENT}"
    log "   Instance ID: ${INSTANCE_ID}"
    log "   Private IP: ${PRIVATE_IP}"
    log "   SSH Key: ${KEY_PATH}"
    log ""
    log "${BLUE}🔐 Access Methods:${NC}"
    log "${GREEN}   Direct Access (Primary):${NC}"
    log "   http://${PRIVATE_IP}:80/pentaho"
    log ""
    log "${YELLOW}   SSH Tunnel (Alternative):${NC}"
    log "   ssh -L 80:localhost:80 -i ${KEY_PATH} ubuntu@${PRIVATE_IP}"
    log "   Then open: http://localhost:80/pentaho"
    log ""
    log "${BLUE}🔑 Login Credentials:${NC}"
    log "   Username: admin"
    log "   Password: password"
    log ""
else
    log "${YELLOW}⚠️  Runtime state file not found - connection info not available${NC}"
fi

log "${BLUE}📝 Log saved to: ${LOG_FILE}${NC}"
log ""
log "${GREEN}Happy analyzing! 🎯${NC}"
