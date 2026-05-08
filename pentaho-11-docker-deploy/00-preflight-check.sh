#!/bin/bash
# 00-preflight-check.sh
# Pre-deployment validation: checks all prerequisites before running 00-full-deploy.sh
# Validates: tools, authentication, AWS resources, env config, SSH keys, plugin URLs, disk space
#
# Usage: ./00-preflight-check.sh <env-file>
# Example: ./00-preflight-check.sh pentaho-deployment-sample-11-1-0-0-120.env

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

# Helper: resolve KEY_PATH for the current environment
resolve_key_path() {
    local kp="$1"
    if [ "$RUN_MODE" = "server" ]; then
        # On the server, look in ~/.ssh/ for just the filename
        local basename
        basename="$(basename "$kp")"
        echo "$HOME/.ssh/$basename"
    else
        echo "$kp"
    fi
}

# ============================================================
# Configuration
# ============================================================
ENV_FILE_NAME="$(basename "${1}")"

if [ -z "$1" ]; then
    echo "❌ Environment file parameter required"
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-dev.env"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/${ENV_FILE_NAME}" ]; then
    echo "❌ Error: Configuration file not found: ${ENV_FILE_NAME}"
    echo "Available files:"
    ls -la "${SCRIPT_DIR}"/*.env 2>/dev/null || echo "None found"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
STATE_FILE_NAME="${ENV_FILE_NAME%.env}-runtime.state"

# ============================================================
# Detect deployment type: PDC vs Pentaho Server
# ============================================================
if [ -n "${PDC_VERSION:-}" ]; then
    DEPLOY_TYPE="pdc"
else
    DEPLOY_TYPE="pentaho"
fi

# ============================================================
# Tracking
# ============================================================
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0
RESULTS=()

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("✅ PASS: $1")
    echo "  ✅ $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("❌ FAIL: $1")
    REMEDIATION+=("❌ $1" "   ↳ $2" "")
    echo "  ❌ $1"
    echo "     ↳ $2"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    RESULTS+=("⚠️  WARN: $1")
    REMEDIATION+=("⚠️  $1" "   ↳ $2" "")
    echo "  ⚠️  $1"
    echo "     ↳ $2"
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    RESULTS+=("⏭️  SKIP: $1")
    echo "  ⏭️  $1 (skipped: $2)"
}

section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

REMEDIATION=()

echo ""
echo "🔍 Pentaho 11 Docker Deployment — Preflight Check"
echo "=================================================="
echo "  Environment File: ${ENV_FILE_NAME}"
if [ "$DEPLOY_TYPE" = "pdc" ]; then
    echo "  Deploy Type:      PDC (Pentaho Data Catalog)"
    echo "  PDC Version:      ${PDC_VERSION:-NOT SET}"
    echo "  PDC Artifact:     ${PDC_ARTIFACT:-NOT SET}"
else
    echo "  Deploy Type:      Pentaho Server"
    echo "  Pentaho Version:  ${PENTAHO_VERSION:-NOT SET}"
fi
echo "  Environment:      ${ENVIRONMENT:-NOT SET}"
echo "  Run Mode:         ${RUN_MODE}"
echo "  Date:             $(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================
# 1. LOCAL TOOLS
# ============================================================
section "1. Local Tools & Commands"

# Check required commands
for cmd in aws ssh scp grep sed awk; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd is installed"
    else
        fail "$cmd is not installed" "Install $cmd (e.g., brew install $cmd)"
    fi
done

# Check okta-aws (local only — not needed on server)
if [ "$RUN_MODE" = "local" ]; then
    if command -v okta-aws &>/dev/null || type okta-aws &>/dev/null 2>&1; then
        pass "okta-aws is available"
    else
        fail "okta-aws is not available" "Ensure okta-aws is installed and your shell config is sourced"
    fi
else
    pass "okta-aws not required on server (using aws CLI directly)"
fi

# Check jq (used in some scripts)
if command -v jq &>/dev/null; then
    pass "jq is installed"
else
    warn "jq is not installed" "Install with: brew install jq (optional but recommended)"
fi

# AWS CLI version
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | head -1)
    pass "AWS CLI version: ${AWS_VERSION}"
fi

# ============================================================
# 2. REQUIRED ENVIRONMENT VARIABLES
# ============================================================
section "2. Required Environment Variables"

# Common vars for both deployment types
COMMON_REQUIRED_VARS=(
    "AWS_PROFILE"
    "AWS_REGION"
    "KEY_NAME"
    "KEY_PATH"
    "PROJECT_NAME"
    "INSTANCE_NAME"
    "AMI_ID"
    "INSTANCE_TYPE"
    "EBS_VOLUME_SIZE"
    "VOLUME_TYPE"
    "ENVIRONMENT"
    "VPC_ID"
    "SUBNET_ID"
    "SECURITY_GROUP_ID"
    "JFROG_TOKEN"
    "DB_TYPE"
)

# Type-specific required vars
if [ "$DEPLOY_TYPE" = "pdc" ]; then
    REQUIRED_VARS=("${COMMON_REQUIRED_VARS[@]}" "PDC_VERSION" "PDC_ARTIFACT" "PDC_JFROG_BASE_URL" "PDC_LICENSE_URL")
else
    REQUIRED_VARS=("${COMMON_REQUIRED_VARS[@]}" "PENTAHO_VERSION" "JFROG_BASE_URL" "LICENSE_URL")
fi

for var in "${REQUIRED_VARS[@]}"; do
    val="${!var}"
    if [ -n "$val" ]; then
        # Mask sensitive values
        if [[ "$var" == "JFROG_TOKEN" ]]; then
            pass "$var is set (${val:0:8}...)"
        else
            pass "$var = ${val}"
        fi
    else
        fail "$var is not set" "Set $var in ${ENV_FILE_NAME}"
    fi
done

# Check optional but important variables
OPTIONAL_VARS=(
    "SSH_USER"
    "PORT"
    "PENTAHO_CONTAINER_CPU_LIMIT"
    "PENTAHO_CONTAINER_MEMORY_LIMIT"
    "PENTAHO_JVM_MIN_HEAP"
    "PENTAHO_JVM_MAX_HEAP"
)

echo ""
echo "  Optional variables:"
for var in "${OPTIONAL_VARS[@]}"; do
    val="${!var}"
    if [ -n "$val" ]; then
        pass "$var = ${val}"
    else
        warn "$var is not set (will use default)" "Set $var in ${ENV_FILE_NAME} if needed"
    fi
done

# ============================================================
# 3. SSH KEY
# ============================================================
section "3. SSH Key Validation"

RESOLVED_KEY_PATH="$(resolve_key_path "${KEY_PATH}")"

if [ -n "${KEY_PATH}" ]; then
    if [ -f "${RESOLVED_KEY_PATH}" ]; then
        pass "SSH key file exists: ${RESOLVED_KEY_PATH}"

        # Check permissions (stat flags differ between macOS and Linux)
        if [ "$RUN_MODE" = "local" ]; then
            KEY_PERMS=$(stat -f "%Lp" "${RESOLVED_KEY_PATH}" 2>/dev/null)
        else
            KEY_PERMS=$(stat -c "%a" "${RESOLVED_KEY_PATH}" 2>/dev/null)
        fi
        if [ "$KEY_PERMS" = "600" ] || [ "$KEY_PERMS" = "400" ]; then
            pass "SSH key permissions are correct (${KEY_PERMS})"
        else
            fail "SSH key permissions are too open (${KEY_PERMS})" "Fix with: chmod 600 ${RESOLVED_KEY_PATH}"
        fi

        # Check key format
        if ssh-keygen -l -f "${RESOLVED_KEY_PATH}" &>/dev/null; then
            KEY_INFO=$(ssh-keygen -l -f "${RESOLVED_KEY_PATH}" 2>&1)
            pass "SSH key is valid: ${KEY_INFO}"
        else
            fail "SSH key file is not a valid key" "Verify ${RESOLVED_KEY_PATH} is a valid PEM private key"
        fi
    else
        fail "SSH key file not found: ${RESOLVED_KEY_PATH}" "Upload the key via Ops Console or place it at ${RESOLVED_KEY_PATH}"
    fi
else
    fail "KEY_PATH is not set" "Set KEY_PATH in ${ENV_FILE_NAME}"
fi

# ============================================================
# 4. AWS AUTHENTICATION
# ============================================================
section "4. AWS Authentication"

AUTH_OK=false
if [ -n "${AWS_PROFILE}" ]; then
    echo "  Testing AWS authentication for profile: ${AWS_PROFILE} (${RUN_MODE} mode)..."
    if aws_cmd "${AWS_PROFILE}" sts get-caller-identity &>/dev/null; then
        CALLER_ID=$(aws_cmd "${AWS_PROFILE}" sts get-caller-identity 2>/dev/null)
        pass "AWS authentication successful"
        if command -v jq &>/dev/null && [ -n "$CALLER_ID" ]; then
            ACCOUNT=$(echo "$CALLER_ID" | jq -r '.Account' 2>/dev/null)
            ARN=$(echo "$CALLER_ID" | jq -r '.Arn' 2>/dev/null)
            if [ -n "$ACCOUNT" ] && [ "$ACCOUNT" != "null" ]; then
                pass "AWS Account: ${ACCOUNT}"
                pass "AWS ARN: ${ARN}"
            fi
        fi
        AUTH_OK=true
    else
        if [ "$RUN_MODE" = "server" ]; then
            fail "AWS authentication failed for profile: ${AWS_PROFILE}" "Sync credentials via Ops Console → Provision → AWS Credentials"
        else
            fail "AWS authentication failed for profile: ${AWS_PROFILE}" "Run: okta-aws ${AWS_PROFILE} sts get-caller-identity   — and resolve any errors"
        fi
    fi
else
    fail "AWS_PROFILE is not set" "Set AWS_PROFILE in ${ENV_FILE_NAME}"
fi

# ============================================================
# 5. AWS RESOURCES (only if auth succeeded)
# ============================================================
section "5. AWS Resources"

if $AUTH_OK; then
    # Check key pair
    if [ -n "${KEY_NAME}" ]; then
        if aws_cmd "${AWS_PROFILE}" ec2 describe-key-pairs --key-names "${KEY_NAME}" --region "${AWS_REGION}" &>/dev/null; then
            pass "AWS key pair exists: ${KEY_NAME}"
        else
            fail "AWS key pair not found: ${KEY_NAME}" "Import your public key in AWS Console → EC2 → Key Pairs, or check KEY_NAME in ${ENV_FILE_NAME}"
        fi
    fi

    # Check VPC
    if [ -n "${VPC_ID}" ]; then
        if aws_cmd "${AWS_PROFILE}" ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${AWS_REGION}" &>/dev/null; then
            pass "VPC exists: ${VPC_ID}"
        else
            fail "VPC not found: ${VPC_ID}" "Verify VPC_ID in ${ENV_FILE_NAME} matches an existing VPC in ${AWS_REGION}"
        fi
    fi

    # Check subnet
    if [ -n "${SUBNET_ID}" ]; then
        if aws_cmd "${AWS_PROFILE}" ec2 describe-subnets --subnet-ids "${SUBNET_ID}" --region "${AWS_REGION}" &>/dev/null; then
            pass "Subnet exists: ${SUBNET_ID}"
        else
            fail "Subnet not found: ${SUBNET_ID}" "Verify SUBNET_ID in ${ENV_FILE_NAME} matches an existing subnet in ${AWS_REGION}"
        fi
    fi

    # Check security group
    if [ -n "${SECURITY_GROUP_ID}" ]; then
        SG_OUTPUT=$(aws_cmd "${AWS_PROFILE}" ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" --region "${AWS_REGION}" 2>&1)
        if [ $? -eq 0 ]; then
            pass "Security group exists: ${SECURITY_GROUP_ID}"

            # Check for SSH inbound rule
            if echo "$SG_OUTPUT" | grep -q '"FromPort": 22'; then
                pass "Security group has SSH (port 22) inbound rule"
            elif echo "$SG_OUTPUT" | grep -q '"IpProtocol": "-1"'; then
                pass "Security group allows all traffic (includes SSH)"
            else
                warn "Security group may not have SSH (port 22) inbound rule" "Ensure inbound SSH is allowed from your IP"
            fi
        else
            fail "Security group not found: ${SECURITY_GROUP_ID}" "Verify SECURITY_GROUP_ID in ${ENV_FILE_NAME}"
        fi
    fi

    # Check AMI
    if [ -n "${AMI_ID}" ]; then
        if aws_cmd "${AWS_PROFILE}" ec2 describe-images --image-ids "${AMI_ID}" --region "${AWS_REGION}" &>/dev/null; then
            pass "AMI exists: ${AMI_ID}"
        else
            fail "AMI not found: ${AMI_ID}" "Verify AMI_ID in ${ENV_FILE_NAME} is available in ${AWS_REGION}"
        fi
    fi
else
    skip "AWS key pair check" "authentication failed"
    skip "VPC check" "authentication failed"
    skip "Subnet check" "authentication failed"
    skip "Security group check" "authentication failed"
    skip "AMI check" "authentication failed"
fi

# ============================================================
# 6. JFROG / ARTIFACT ACCESS
# ============================================================
section "6. JFrog Artifact Access"

if [ "$DEPLOY_TYPE" = "pdc" ]; then
    # ── PDC artifact checks ──
    if [ -n "${JFROG_TOKEN}" ] && [ -n "${PDC_JFROG_BASE_URL}" ] && [ -n "${PDC_VERSION}" ] && [ -n "${PDC_ARTIFACT}" ]; then
        PDC_ARTIFACT_URL="${PDC_JFROG_BASE_URL}/release-v${PDC_VERSION}/${PDC_ARTIFACT}"

        echo "  Testing JFrog connectivity for PDC artifact..."

        # Test compose bundle URL
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "${PDC_ARTIFACT_URL}" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            pass "PDC artifact accessible (HTTP ${HTTP_CODE}): ${PDC_ARTIFACT}"
        elif [ "$HTTP_CODE" = "000" ]; then
            warn "Could not verify PDC artifact (network or curl unavailable)" "Manually verify: curl -H 'Authorization: Bearer <token>' --head ${PDC_ARTIFACT_URL}"
        elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
            fail "JFrog authentication failed (HTTP ${HTTP_CODE})" "JFROG_TOKEN may be expired. Get a new token from https://one.hitachivantara.com/ → Set Me Up"
        elif [ "$HTTP_CODE" = "404" ]; then
            fail "PDC artifact not found (HTTP 404): ${PDC_ARTIFACT}" "Browse release-v${PDC_VERSION}/ in JFrog and verify the filename in PDC_ARTIFACT"
        else
            warn "Unexpected JFrog response (HTTP ${HTTP_CODE}) for PDC artifact" "Manually verify artifact exists at ${PDC_ARTIFACT_URL}"
        fi
    else
        if [ -z "${JFROG_TOKEN}" ]; then
            fail "JFROG_TOKEN is not set" "Set JFROG_TOKEN in ${ENV_FILE_NAME}"
        fi
        if [ -z "${PDC_JFROG_BASE_URL}" ]; then
            fail "PDC_JFROG_BASE_URL is not set" "Set PDC_JFROG_BASE_URL in ${ENV_FILE_NAME}"
        fi
        if [ -z "${PDC_VERSION}" ]; then
            fail "PDC_VERSION is not set" "Set PDC_VERSION in ${ENV_FILE_NAME}"
        fi
        if [ -z "${PDC_ARTIFACT}" ]; then
            fail "PDC_ARTIFACT is not set" "Browse release-v${PDC_VERSION}/ in JFrog and set PDC_ARTIFACT to the *-compose.tgz filename"
        fi
    fi
else
    # ── Pentaho Server artifact checks ──
    if [ -n "${JFROG_TOKEN}" ] && [ -n "${JFROG_BASE_URL}" ] && [ -n "${PENTAHO_VERSION}" ]; then
        # Build the expected artifact URLs and test with a HEAD request
        IMAGE_URL="${JFROG_BASE_URL}/${PENTAHO_VERSION}/images/pentaho-server-${PENTAHO_VERSION}.tar.gz"
    ONPREM_URL="${JFROG_BASE_URL}/${PENTAHO_VERSION}/dists/on-prem-${PENTAHO_VERSION}.zip"

    echo "  Testing JFrog connectivity..."

    # Test image URL
    HTTP_CODE=$(aws_cmd "${AWS_PROFILE}" -- curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "${IMAGE_URL}" 2>/dev/null || \
                curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "${IMAGE_URL}" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        pass "Pentaho server image accessible (HTTP ${HTTP_CODE}): pentaho-server-${PENTAHO_VERSION}.tar.gz"
    elif [ "$HTTP_CODE" = "000" ]; then
        warn "Could not verify JFrog artifact access (network or curl unavailable)" "Manually verify: curl -H 'Authorization: Bearer <token>' --head ${IMAGE_URL}"
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        fail "JFrog authentication failed (HTTP ${HTTP_CODE})" "JFROG_TOKEN may be expired. Get a new token from https://one.hitachivantara.com/ → Set Me Up"
    elif [ "$HTTP_CODE" = "404" ]; then
        fail "Pentaho server image not found (HTTP 404)" "Verify PENTAHO_VERSION=${PENTAHO_VERSION} and JFROG_BASE_URL are correct"
    else
        warn "Unexpected JFrog response (HTTP ${HTTP_CODE}) for server image" "Manually verify artifact exists at ${IMAGE_URL}"
    fi

    # Test on-prem URL
    HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "${ONPREM_URL}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE2" = "200" ] || [ "$HTTP_CODE2" = "302" ]; then
        pass "On-prem distribution accessible (HTTP ${HTTP_CODE2}): on-prem-${PENTAHO_VERSION}.zip"
    elif [ "$HTTP_CODE2" = "000" ]; then
        warn "Could not verify on-prem distribution access" "Manually verify: curl -H 'Authorization: Bearer <token>' --head ${ONPREM_URL}"
    elif [ "$HTTP_CODE2" = "401" ] || [ "$HTTP_CODE2" = "403" ]; then
        fail "JFrog auth failed for on-prem distribution (HTTP ${HTTP_CODE2})" "JFROG_TOKEN may be expired or wrong repo. Check JFROG_BASE_URL"
    elif [ "$HTTP_CODE2" = "404" ]; then
        fail "On-prem distribution not found (HTTP 404)" "Verify PENTAHO_VERSION=${PENTAHO_VERSION} exists in the repo at JFROG_BASE_URL"
    else
        warn "Unexpected JFrog response (HTTP ${HTTP_CODE2}) for on-prem dist" "Manually verify artifact exists at ${ONPREM_URL}"
    fi
else
    if [ -z "${JFROG_TOKEN}" ]; then
        fail "JFROG_TOKEN is not set" "Set JFROG_TOKEN in ${ENV_FILE_NAME}"
    fi
    if [ -z "${JFROG_BASE_URL}" ]; then
        fail "JFROG_BASE_URL is not set" "Set JFROG_BASE_URL in ${ENV_FILE_NAME}"
    fi
fi
fi  # end DEPLOY_TYPE branch

# ============================================================
# 7. PLUGIN URLS (Pentaho Server only — PDC has no plugins)
# ============================================================
section "7. Plugin Configuration"

if [ "$DEPLOY_TYPE" = "pdc" ]; then
    skip "Plugin checks" "not applicable for PDC deployments"
else

PLUGIN_COUNT=0
PLUGIN_FAIL=0

if [ -n "${PLUGINS_TYPICAL}" ]; then
    echo "  Typical plugins:"
    while IFS= read -r url; do
        url=$(echo "$url" | xargs)  # trim whitespace
        [ -z "$url" ] && continue
        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
        PLUGIN_FILENAME=$(basename "$url")

        # Check URL is well-formed
        if [[ "$url" == https://* ]]; then
            # Quick HEAD check
            P_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "$url" 2>/dev/null || echo "000")
            if [ "$P_HTTP" = "200" ] || [ "$P_HTTP" = "302" ]; then
                pass "Plugin accessible: ${PLUGIN_FILENAME}"
            elif [ "$P_HTTP" = "000" ]; then
                warn "Could not verify plugin: ${PLUGIN_FILENAME}" "Check network or manually verify URL"
            elif [ "$P_HTTP" = "404" ]; then
                fail "Plugin not found (404): ${PLUGIN_FILENAME}" "Verify URL: ${url}"
                PLUGIN_FAIL=$((PLUGIN_FAIL + 1))
            else
                warn "Plugin returned HTTP ${P_HTTP}: ${PLUGIN_FILENAME}" "Verify URL: ${url}"
            fi
        else
            fail "Invalid plugin URL: ${url}" "Plugin URLs must start with https://"
            PLUGIN_FAIL=$((PLUGIN_FAIL + 1))
        fi
    done <<< "${PLUGINS_TYPICAL}"
else
    warn "PLUGINS_TYPICAL is not set" "No typical plugins will be installed. Set PLUGINS_TYPICAL if needed."
fi

if [ -n "${PLUGINS_SPECIAL}" ]; then
    echo ""
    echo "  Special plugins:"
    while IFS= read -r entry; do
        entry=$(echo "$entry" | xargs)
        [ -z "$entry" ] && continue
        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))

        PLUGIN_NAME="${entry%%|*}"
        PLUGIN_SOURCE="${entry#*|}"

        if [[ "$PLUGIN_SOURCE" == file://* ]]; then
            # Local file plugin
            LOCAL_FILE="${PLUGIN_SOURCE#file://}"
            FULL_PATH="${SCRIPT_DIR}/downloads/plugins/${PENTAHO_VERSION}/${LOCAL_FILE}"
            if [ -f "$FULL_PATH" ]; then
                pass "Local plugin file exists: ${PLUGIN_NAME} → ${LOCAL_FILE}"
            else
                fail "Local plugin file not found: ${PLUGIN_NAME}" "Expected at: ${FULL_PATH}"
                PLUGIN_FAIL=$((PLUGIN_FAIL + 1))
            fi
        elif [[ "$PLUGIN_SOURCE" == https://* ]]; then
            PLUGIN_FILENAME=$(basename "$PLUGIN_SOURCE")
            P_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${JFROG_TOKEN}" --head "$PLUGIN_SOURCE" 2>/dev/null || echo "000")
            if [ "$P_HTTP" = "200" ] || [ "$P_HTTP" = "302" ]; then
                pass "Special plugin accessible: ${PLUGIN_NAME} → ${PLUGIN_FILENAME}"
            elif [ "$P_HTTP" = "000" ]; then
                warn "Could not verify special plugin: ${PLUGIN_NAME}" "Check network or manually verify URL"
            elif [ "$P_HTTP" = "404" ]; then
                fail "Special plugin not found (404): ${PLUGIN_NAME}" "Verify URL: ${PLUGIN_SOURCE}"
                PLUGIN_FAIL=$((PLUGIN_FAIL + 1))
            else
                warn "Special plugin returned HTTP ${P_HTTP}: ${PLUGIN_NAME}" "Verify URL: ${PLUGIN_SOURCE}"
            fi
        else
            fail "Invalid plugin source for ${PLUGIN_NAME}: ${PLUGIN_SOURCE}" "Must start with https:// or file://"
            PLUGIN_FAIL=$((PLUGIN_FAIL + 1))
        fi
    done <<< "${PLUGINS_SPECIAL}"
fi

echo ""
echo "  Plugin summary: ${PLUGIN_COUNT} plugins configured, ${PLUGIN_FAIL} with issues"
fi  # end DEPLOY_TYPE=pentaho plugin checks

# ============================================================
# 8. DEPLOYMENT SCRIPTS
# ============================================================
section "8. Deployment Scripts"

if [ "$DEPLOY_TYPE" = "pdc" ]; then
    EXPECTED_SCRIPTS=(
        "00-full-deploy-pdc.sh"
        "01-auth-okta-aws.sh"
        "02-create-ec2.sh"
        "03-check-ec2.sh"
        "30-deploy-pdc.sh"
        "96-ssh-into-instance.sh"
        "97-monitor-resources.sh"
        "98-diagnose-container.sh"
        "99-teardown.sh"
    )
else
    EXPECTED_SCRIPTS=(
        "00-full-deploy.sh"
        "01-auth-okta-aws.sh"
    "02-create-ec2.sh"
    "03-check-ec2.sh"
    "10-deploy-pentaho.sh"
    "20-deploy-all-plugins.sh"
    "21-deploy-plugin.sh"
    "22-install-plugin-from-local.sh"
    "90-restart-pentaho-container.sh"
    "91-up-pentaho-container.sh"
    "92-down-pentaho-container.sh"
    "93-tail-catalina-log.sh"
    "94-get-docker-logs.sh"
    "95-ssh-into-container.sh"
    "96-ssh-into-instance.sh"
    "97-monitor-resources.sh"
    "98-diagnose-container.sh"
    "99-teardown.sh"
)
fi  # end DEPLOY_TYPE script list

for script in "${EXPECTED_SCRIPTS[@]}"; do
    FULL="${SCRIPT_DIR}/${script}"
    if [ -f "$FULL" ]; then
        if [ -x "$FULL" ]; then
            pass "${script} exists and is executable"
        else
            fail "${script} exists but is NOT executable" "Fix with: chmod +x ${FULL}"
        fi
    else
        fail "${script} is missing" "Expected at: ${FULL}"
    fi
done

# ============================================================
# 9. EXISTING STATE (check for conflicts)
# ============================================================
section "9. Existing State Check"

STATE_PATH="${SCRIPT_DIR}/${STATE_FILE_NAME}"
if [ -f "$STATE_PATH" ]; then
    source "$STATE_PATH"
    warn "Runtime state file already exists: ${STATE_FILE_NAME}" "An instance may already be running. Check with: ./03-check-ec2.sh ${ENV_FILE_NAME}"
    if [ -n "${INSTANCE_ID}" ]; then
        echo "     Existing Instance ID: ${INSTANCE_ID}"
        echo "     Existing IP: ${SSH_IP:-${PUBLIC_IP:-${PRIVATE_IP:-unknown}}}"
    fi
else
    pass "No existing state file (clean deployment)"
fi

# ============================================================
# 10. LOCAL DISK SPACE
# ============================================================
section "10. Local Disk Space"

# Note: Pentaho images and distributions are downloaded directly on the EC2 instance,
# not locally. Local space is only needed for scripts, env files, softwareOverride/,
# and any local plugin zips used with 22-install-plugin-from-local.sh.

AVAILABLE_KB=$(df -k "${SCRIPT_DIR}" | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))

if [ "$AVAILABLE_GB" -ge 1 ]; then
    pass "Local disk space: ${AVAILABLE_GB} GB available (downloads happen on EC2, minimal local space needed)"
else
    warn "Local disk space is very low: ${AVAILABLE_GB} GB" "Only needed for scripts and local plugin files, but consider freeing space"
fi

# ============================================================
# 11. SOFTWARE OVERRIDE DIRECTORY
# ============================================================
section "11. Software Override Directory"

if [ "$DEPLOY_TYPE" = "pdc" ]; then
    skip "softwareOverride check" "not applicable for PDC deployments"
else
if [ -d "$OVERRIDE_DIR" ]; then
    pass "softwareOverride/ directory exists"

    # Check for expected subdirectories
    for subdir in "1_drivers" "2_repository" "4_others"; do
        if [ -d "${OVERRIDE_DIR}/${subdir}" ]; then
            FILE_COUNT=$(find "${OVERRIDE_DIR}/${subdir}" -type f 2>/dev/null | wc -l | xargs)
            pass "softwareOverride/${subdir}/ exists (${FILE_COUNT} files)"
        else
            warn "softwareOverride/${subdir}/ does not exist" "Create if you need custom ${subdir} (optional)"
        fi
    done
else
    warn "softwareOverride/ directory does not exist" "Create it if you need custom drivers or configs (optional)"
fi
fi  # end DEPLOY_TYPE=pentaho softwareOverride check

# ============================================================
# 12. CONFIGURATION SANITY CHECKS
# ============================================================
section "12. Configuration Sanity Checks"

# Check DB_TYPE is valid
if [ -n "${DB_TYPE}" ]; then
    case "${DB_TYPE}" in
        postgres|mysql|sqlserver|oracle)
            pass "DB_TYPE is valid: ${DB_TYPE}"
            ;;
        *)
            fail "DB_TYPE is invalid: ${DB_TYPE}" "Must be one of: postgres, mysql, sqlserver, oracle"
            ;;
    esac
fi

# Check version format
if [ "$DEPLOY_TYPE" = "pdc" ]; then
    if [ -n "${PDC_VERSION}" ]; then
        if [[ "${PDC_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            pass "PDC_VERSION format is valid: ${PDC_VERSION}"
        else
            warn "PDC_VERSION format looks unusual: ${PDC_VERSION}" "Expected format: X.Y.Z (e.g., 10.2.10)"
        fi
    fi
else
    if [ -n "${PENTAHO_VERSION}" ]; then
        if [[ "${PENTAHO_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]]; then
            pass "PENTAHO_VERSION format is valid: ${PENTAHO_VERSION}"
        else
            warn "PENTAHO_VERSION format looks unusual: ${PENTAHO_VERSION}" "Expected format: X.Y.Z.W-NNN (e.g., 11.0.0.1-259)"
        fi
    fi
fi

# Check VPC/Subnet/SG format
if [ -n "${VPC_ID}" ] && [[ ! "${VPC_ID}" =~ ^vpc- ]]; then
    fail "VPC_ID format invalid: ${VPC_ID}" "Must start with vpc-"
fi
if [ -n "${SUBNET_ID}" ] && [[ ! "${SUBNET_ID}" =~ ^subnet- ]]; then
    fail "SUBNET_ID format invalid: ${SUBNET_ID}" "Must start with subnet-"
fi
if [ -n "${SECURITY_GROUP_ID}" ] && [[ ! "${SECURITY_GROUP_ID}" =~ ^sg- ]]; then
    fail "SECURITY_GROUP_ID format invalid: ${SECURITY_GROUP_ID}" "Must start with sg-"
fi
if [ -n "${AMI_ID}" ] && [[ ! "${AMI_ID}" =~ ^ami- ]]; then
    fail "AMI_ID format invalid: ${AMI_ID}" "Must start with ami-"
fi

# Check JVM heap makes sense relative to container memory
if [ -n "${PENTAHO_JVM_MAX_HEAP}" ] && [ -n "${PENTAHO_CONTAINER_MEMORY_LIMIT}" ]; then
    # Extract numbers (strip units)
    JVM_NUM=$(echo "${PENTAHO_JVM_MAX_HEAP}" | grep -o '[0-9]*')
    JVM_UNIT=$(echo "${PENTAHO_JVM_MAX_HEAP}" | grep -o '[a-zA-Z]*')
    CONTAINER_NUM=$(echo "${PENTAHO_CONTAINER_MEMORY_LIMIT}" | grep -o '[0-9.]*')
    CONTAINER_UNIT=$(echo "${PENTAHO_CONTAINER_MEMORY_LIMIT}" | grep -o '[a-zA-Z]*')

    # Normalize to GB for comparison
    JVM_GB=$JVM_NUM
    if [[ "$JVM_UNIT" == "m" || "$JVM_UNIT" == "M" ]]; then
        JVM_GB=$(echo "scale=1; $JVM_NUM / 1024" | bc 2>/dev/null || echo "0")
    fi
    CONTAINER_GB=$CONTAINER_NUM
    if [[ "$CONTAINER_UNIT" == "MB" || "$CONTAINER_UNIT" == "mb" ]]; then
        CONTAINER_GB=$(echo "scale=1; $CONTAINER_NUM / 1024" | bc 2>/dev/null || echo "0")
    fi

    if (( $(echo "$JVM_GB < $CONTAINER_GB" | bc 2>/dev/null || echo "1") )); then
        pass "JVM max heap (${PENTAHO_JVM_MAX_HEAP}) fits within container memory (${PENTAHO_CONTAINER_MEMORY_LIMIT})"
    else
        fail "JVM max heap (${PENTAHO_JVM_MAX_HEAP}) exceeds container memory (${PENTAHO_CONTAINER_MEMORY_LIMIT})" "Reduce PENTAHO_JVM_MAX_HEAP or increase PENTAHO_CONTAINER_MEMORY_LIMIT"
    fi
fi

# Check PORT is reasonable
if [ -n "${PORT}" ]; then
    if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] 2>/dev/null; then
        pass "PORT is valid: ${PORT}"
    else
        fail "PORT is invalid: ${PORT}" "Must be between 1 and 65535"
    fi
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PREFLIGHT CHECK SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ✅ Passed:  ${PASS_COUNT}"
echo "  ❌ Failed:  ${FAIL_COUNT}"
echo "  ⚠️  Warnings: ${WARN_COUNT}"
echo "  ⏭️  Skipped: ${SKIP_COUNT}"
echo ""

if [ ${#REMEDIATION[@]} -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  REMEDIATION STEPS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    for line in "${REMEDIATION[@]}"; do
        echo "  $line"
    done
fi

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🟢 All critical checks passed. Ready to deploy!"
    echo ""
    if [ "$DEPLOY_TYPE" = "pdc" ]; then
        echo "  Run: ./00-full-deploy-pdc.sh ${ENV_FILE_NAME}"
    else
        echo "  Run: ./00-full-deploy.sh ${ENV_FILE_NAME}"
    fi
    echo ""
    exit 0
else
    echo "🔴 ${FAIL_COUNT} critical issue(s) must be resolved before deployment."
    echo ""
    exit 1
fi
