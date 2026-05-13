#!/bin/bash
# 51-test-marquez.sh
# Test Marquez connectivity and send a sample OpenLineage event from local machine.
#
# Usage: ./51-test-marquez.sh marquez.env

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file>"
    echo "Example: $0 marquez.env"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"

# Resolve state file
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

API_URL="http://${SSH_IP}:${MARQUEZ_API_PORT:-5000}"
WEB_URL="http://${SSH_IP}:${MARQUEZ_WEB_PORT:-3000}"
ADMIN_URL="http://${SSH_IP}:${MARQUEZ_ADMIN_PORT:-5001}"

echo "🔍 Marquez Connectivity Test"
echo "=============================="
echo "   API:     ${API_URL}"
echo "   Web UI:  ${WEB_URL}"
echo "   Health:  ${ADMIN_URL}/healthcheck"
echo ""

PASS=0
FAIL=0

check() {
    local label="$1"
    local url="$2"
    if curl -sf --connect-timeout 5 "${url}" > /dev/null 2>&1; then
        echo "✅ ${label}"
        PASS=$((PASS+1))
    else
        echo "❌ ${label} — could not reach ${url}"
        FAIL=$((FAIL+1))
    fi
}

echo "--- Health checks ---"
check "Health endpoint"   "${ADMIN_URL}/healthcheck"
check "API /namespaces"   "${API_URL}/api/v1/namespaces"
check "Web UI"            "${WEB_URL}"

echo ""
echo "--- Sending test OpenLineage event ---"

EVENT_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${API_URL}/api/v1/lineage" \
    -H "Content-Type: application/json" \
    -d '{
        "eventType": "COMPLETE",
        "eventTime": "'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'",
        "run": {
            "runId": "test-run-'"$(date +%s)"'"
        },
        "job": {
            "namespace": "pentaho",
            "name": "test-connectivity-job"
        },
        "inputs": [],
        "outputs": [],
        "producer": "https://pentaho.hitachivantara.com",
        "schemaURL": "https://openlineage.io/spec/1-0-5/OpenLineage.json#/definitions/RunEvent"
    }')

if [ "${EVENT_RESPONSE}" = "200" ] || [ "${EVENT_RESPONSE}" = "201" ]; then
    echo "✅ OpenLineage event accepted (HTTP ${EVENT_RESPONSE})"
    PASS=$((PASS+1))
else
    echo "❌ OpenLineage event rejected (HTTP ${EVENT_RESPONSE})"
    FAIL=$((FAIL+1))
fi

echo ""
echo "--- Verifying event was stored ---"
JOBS_RESPONSE=$(curl -sf "${API_URL}/api/v1/namespaces/pentaho/jobs" 2>/dev/null || echo "")
if echo "${JOBS_RESPONSE}" | grep -q "test-connectivity-job"; then
    echo "✅ Test job visible in Marquez"
    PASS=$((PASS+1))
else
    echo "⚠️  Test job not yet visible (may need a moment to index)"
fi

echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [ "${FAIL}" -eq 0 ]; then
    echo "🎉 Marquez is ready to receive Pentaho OpenLineage events!"
    echo ""
    echo "Add this to ~/.kettle/openlineageConfig.yml on your Pentaho client:"
    echo ""
    echo "version: 0.0.1"
    echo "consumers:"
    echo "  http:"
    echo "    - name: Marquez"
    echo "      url: \"${API_URL}\""
    echo "      endpoint: \"/api/v1/lineage\""
    echo "console:"
    echo "file:"
    echo "  - path: \"/Users/khaas/tmp/\""
    echo ""
    echo "Web UI: ${WEB_URL}"
else
    echo "⚠️  Some checks failed. Troubleshooting:"
    echo "   - Confirm the EC2 is running:      ./03-check-ec2.sh ${ENV_FILE_NAME}"
    echo "   - Check Marquez container logs:    ssh into instance, then: docker compose -C ~/marquez logs marquez"
    echo "   - Re-deploy Marquez:               ./50-deploy-marquez.sh ${ENV_FILE_NAME}"
    exit 1
fi
