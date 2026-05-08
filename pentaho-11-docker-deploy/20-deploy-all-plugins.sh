#!/bin/bash

# Install All Plugins Script
# Deploys multiple plugins and restarts the server once at the end

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 pentaho-deployment-sample-11-1-0-0-120.env"
    echo ""
    echo "This script will install all available plugins:"
    echo "  - pdd-plugin-ee (Pipeline Data Designer)"
    echo "  - paz-plugin-ee (Pentaho Analysis)"
    echo "  - webttle-plugins-ee-client (Pipeline Designer/Webttle)"
    echo "  - pas-scheduler (PAS Scheduler)"
    echo "  - pir-plugin-ee (Interactive Reports)"
    echo ""
    echo "The Pentaho server will be restarted once after all plugins are installed."
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state file: explicit arg > env var > newest match > legacy derivation
if [ -n "${2:-}" ]; then
    STATE_FILE_NAME="$(basename "$2")"
elif [ -n "${STATE_FILE:-}" ]; then
    STATE_FILE_NAME="$(basename "$STATE_FILE")"
else
    _found=$(ls -t "${SCRIPT_DIR}"/${ENV_FILE_NAME%.env}*-runtime.state 2>/dev/null | head -1)
    STATE_FILE_NAME="${_found:+$(basename "$_found")}"
    STATE_FILE_NAME="${STATE_FILE_NAME:-${ENV_FILE_NAME%.env}-runtime.state}"
fi

# Load environment variables to get SSH connection info
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

echo "🚀 Installing All Pentaho Plugins"
echo "===================================="
echo "📋 Environment: ${ENVIRONMENT}"
echo "📋 Version: ${PENTAHO_VERSION}"
echo "📋 EC2 Instance: ${SSH_IP}"
echo ""

# Build combined plugin list from both TYPICAL and SPECIAL
PLUGIN_LIST=()

# Add typical plugins (URLs) - use eval to expand ${PENTAHO_VERSION}
while IFS= read -r url; do
    url=$(echo "$url" | xargs)
    [[ -z "$url" ]] && continue
    # Expand any embedded variables like ${PENTAHO_VERSION}
    eval "expanded_url=\"$url\""
    PLUGIN_LIST+=("$expanded_url")
done <<< "$PLUGINS_TYPICAL"

# Add special plugins (names) - use eval to expand ${PENTAHO_VERSION}
while IFS='|' read -r name url; do
    name=$(echo "$name" | xargs)
    [[ -z "$name" ]] && continue
    # Expand any embedded variables in the URL (for special plugins)
    eval "expanded_url=\"$url\""
    # Pass the name (since 21-deploy-plugin.sh looks up special plugins by name)
    PLUGIN_LIST+=("$name")
done <<< "$PLUGINS_SPECIAL"

if [ ${#PLUGIN_LIST[@]} -eq 0 ]; then
    echo "❌ Error: No plugins found in PLUGINS_TYPICAL or PLUGINS_SPECIAL configuration"
    exit 1
fi

echo "📦 Plugins to install (${#PLUGIN_LIST[@]} total):"
for plugin in "${PLUGIN_LIST[@]}"; do
    if [[ "$plugin" =~ ^https?:// ]]; then
        plugin_name=$(basename "$plugin" .zip)
        echo "   - $plugin_name (TYPICAL)"
    else
        echo "   - $plugin (SPECIAL)"
    fi
done
echo ""

# Wait for Pentaho server to be fully ready before installing plugins
echo "⏳ Checking Pentaho Server Readiness"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

MAX_WAIT=300  # 5 minutes max wait
ELAPSED=0
CHECK_INTERVAL=10

echo "Waiting for Pentaho server to be fully initialized..."
echo "This may take a few minutes after initial deployment."
echo ""

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if container is running and check for "Server startup" in logs
    if ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} \
        "docker ps -q -f name=pentaho-server-${DB_TYPE}.*pentaho-server | xargs -r docker logs 2>&1 | grep -q 'Server startup in'" 2>/dev/null; then
        echo "✅ Pentaho server is ready!"
        echo ""
        break
    fi
    
    echo "⏱️  Waiting for server startup... (${ELAPSED}s / ${MAX_WAIT}s)"
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "⚠️  Warning: Server readiness check timed out after ${MAX_WAIT}s"
    echo "   Proceeding anyway, but plugins may fail if server is not ready."
    echo ""
fi

echo "⚙️  All plugins will be installed without restarting between each."
echo "⚙️  Server will restart once at the end."
echo ""

INSTALLED_COUNT=0
FAILED_PLUGINS=()

# Install each plugin with --no-restart flag
for PLUGIN in "${PLUGIN_LIST[@]}"; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Installing plugin: ${PLUGIN}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if "${SCRIPT_DIR}/21-deploy-plugin.sh" --no-restart "${ENV_FILE_NAME}" "${PLUGIN}"; then
        echo "✅ ${PLUGIN} installed successfully"
        ((INSTALLED_COUNT++))
    else
        echo "❌ Failed to install ${PLUGIN}"
        FAILED_PLUGINS+=("${PLUGIN}")
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Installation Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Successfully installed: ${INSTALLED_COUNT}/${#PLUGIN_LIST[@]} plugins"

if [ ${#FAILED_PLUGINS[@]} -gt 0 ]; then
    echo "❌ Failed plugins:"
    for PLUGIN in "${FAILED_PLUGINS[@]}"; do
        echo "   - ${PLUGIN}"
    done
    echo ""
    echo "⚠️  Proceeding with server restart despite failures"
fi

echo ""
echo "🔄 Restarting Pentaho server..."
echo ""

# Restart the Pentaho container once
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "docker restart \$(docker ps -q -f name=pentaho-server)"

echo ""
echo "🎉 All Plugins Deployment Complete!"
echo ""
echo "✅ Installed ${INSTALLED_COUNT}/${#PLUGINS[@]} plugins"
echo "✅ Pentaho server restarted"
echo "🌐 Access: http://${SSH_IP}/pentaho"
echo "👤 Login: admin/password"
echo ""

if [ ${#FAILED_PLUGINS[@]} -gt 0 ]; then
    echo "⚠️  Note: Some plugins failed to install. Check the logs above for details."
    echo ""
fi
