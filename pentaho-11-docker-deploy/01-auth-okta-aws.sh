#!/bin/bash
# 01-auth-okta-aws.sh
# Authenticate with AWS using Okta-AWS (local Mac) or verify AWS CLI credentials (server)

set -e

# ============================================================
# Detect environment: local Mac vs remote server
# ============================================================
if [[ "$(uname)" == "Darwin" ]]; then
    RUN_MODE="local"
    # Source shell configuration to get okta-aws function
    if [ -f ~/.zshrc ]; then
        source ~/.zshrc
    elif [ -f ~/.bashrc ]; then
        source ~/.bashrc
    fi
    # Check if okta-aws is available
    if ! command -v okta-aws &> /dev/null; then
        echo "❌ Error: okta-aws command not found"
        echo "Please ensure okta-aws is installed and configured"
        exit 1
    fi
else
    RUN_MODE="server"
fi

# Helper: run an AWS CLI command using okta-aws (local) or aws --profile (server)
aws_cmd() {
    local profile="$1"
    shift
    if [ "$RUN_MODE" = "local" ]; then
        okta-aws "$profile" "$@"
    else
        aws --profile "$profile" "$@"
    fi
}

# Configuration
ENV_FILE_NAME="$(basename "${1:-pentaho-deployment-sample-11-1-0-0-120.env}")"

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    echo ""
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-120.env"
    echo "Example: $0 pentaho-deployment-dev.env"
    echo ""
    echo "Available configuration files:"
    ls -1 "${SCRIPT_DIR}"/pentaho-deployment-*.env 2>/dev/null | xargs -I{} basename {} | sed 's/^/  - /' || echo "  None found"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"

echo "🔐 AWS Authentication"
echo "==============================="
echo "📋 Environment: ${ENVIRONMENT:-${ENV_FILE_NAME}}"
echo "📋 AWS Profile: ${AWS_PROFILE}"
echo "📋 AWS Region: ${AWS_REGION}"
echo "📋 Mode: ${RUN_MODE}"
echo ""

# Attempt authentication
echo "🔄 Verifying AWS credentials..."
if [ "$RUN_MODE" = "local" ]; then
    echo "Command: okta-aws ${AWS_PROFILE} sts get-caller-identity"
else
    echo "Command: aws --profile ${AWS_PROFILE} sts get-caller-identity"
fi
echo ""

if aws_cmd ${AWS_PROFILE} sts get-caller-identity; then
    echo ""
    echo "✅ Authentication successful!"
    echo ""
    echo "You can now run deployment scripts for environment: ${ENV_FILE_NAME}"
    echo ""
    echo "Next steps:"
    if [ -n "${PDC_VERSION:-}" ]; then
        echo "  1. Full deployment:    ./00-full-deploy-pdc.sh ${ENV_FILE_NAME}"
        echo "  2. Create EC2:         ./02-create-ec2.sh ${ENV_FILE_NAME}"
        echo "  3. Check EC2:          ./03-check-ec2.sh ${ENV_FILE_NAME}"
        echo "  4. Deploy PDC:         ./30-deploy-pdc.sh ${ENV_FILE_NAME}"
    else
        echo "  1. Full deployment:    ./00-full-deploy.sh ${ENV_FILE_NAME}"
        echo "  2. Create EC2:         ./02-create-ec2.sh ${ENV_FILE_NAME}"
        echo "  3. Check EC2:          ./03-check-ec2.sh ${ENV_FILE_NAME}"
        echo "  4. Deploy Pentaho:     ./10-deploy-pentaho.sh ${ENV_FILE_NAME}"
        echo "  5. Deploy plugins:     ./20-deploy-all-plugins.sh ${ENV_FILE_NAME}"
    fi
else
    echo ""
    echo "❌ Authentication failed for profile: ${AWS_PROFILE}"
    echo ""
    echo "Troubleshooting:"
    if [ "$RUN_MODE" = "local" ]; then
        echo "  1. Verify your Okta credentials are correct"
        echo "  2. Check that the AWS_PROFILE in your .env file matches your Okta-AWS configuration"
        echo "  3. Ensure your Okta session hasn't expired"
        echo "  4. Try running manually: okta-aws ${AWS_PROFILE} sts get-caller-identity"
    else
        echo "  1. Verify AWS CLI is configured with the correct profile"
        echo "  2. Check credentials: aws --profile ${AWS_PROFILE} sts get-caller-identity"
        echo "  3. Ensure IAM role/credentials are valid and not expired"
    fi
    exit 1
fi
