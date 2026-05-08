#!/bin/bash

# ================================================================================================
# Monitor Container and JVM Resources
# ================================================================================================
# This script displays real-time resource usage including:
#   - Docker container memory/CPU limits and actual usage
#   - JVM heap memory settings and actual usage
#   - Host system memory and CPU
# Usage: ./98-monitor-resources.sh <env-file> [db-type]
# Example: ./98-monitor-resources.sh pentaho-deployment-sample-11-1-0-0-120.env
# Example: ./98-monitor-resources.sh pentaho-deployment-sample-11-1-0-0-120.env postgres
# ================================================================================================

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file> [db-type]"
    echo ""
    echo "Arguments:"
    echo "  env-file  - Required. Environment file (e.g., pentaho-deployment-sample-11-1-0-0-120.env)"
    echo "  db-type   - Optional. Database type (postgres, mysql, sqlserver, oracle). Default: postgres"
    echo ""
    echo "Examples:"
    echo "  $0 pentaho-deployment-sample-11-1-0-0-120.env                # Monitor default postgres container"
    echo "  $0 pentaho-deployment-sample-11-1-0-0-120.env mysql          # Monitor mysql container"
    exit 1
fi

ENV_FILE_NAME="$(basename "$1")"
DB_TYPE="${2:-postgres}"

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
    echo "❌ Environment file not found: ${ENV_FILE_NAME}"
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/${STATE_FILE_NAME}" ]; then
    echo "❌ Runtime state file not found: ${STATE_FILE_NAME}"
    exit 1
fi

source "${SCRIPT_DIR}/${ENV_FILE_NAME}"
source "${SCRIPT_DIR}/_shared-helpers.sh"
KEY_PATH="$(resolve_key_path "${KEY_PATH}")"
source "${SCRIPT_DIR}/${STATE_FILE_NAME}"

# Resolve KEY_PATH to server-local key if original path doesn't exist
[ ! -f "$KEY_PATH" ] && KEY_PATH="$HOME/.ssh/$(basename "$KEY_PATH")"

SSH_USER=${SSH_USER:-ubuntu}

echo "================================================================================================"
echo "📊 Resource Monitoring for Pentaho Deployment"
echo "================================================================================================"
echo "Environment:    ${ENVIRONMENT}"
echo "EC2 Instance:   ${INSTANCE_ID} (${SSH_IP})"
echo "Database Type:  ${DB_TYPE}"
echo "================================================================================================"
echo ""

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "export DB_TYPE='${DB_TYPE}'; bash -s" <<'ENDSSH'
set -e

# Find pentaho-server container
CONTAINER_ID=$(docker ps --format '{{.ID}} {{.Names}}' | grep -E "pentaho-server-${DB_TYPE}.*pentaho-server" | awk '{print $1}' | head -n1)
CONTAINER_NAME=$(docker ps --format '{{.ID}} {{.Names}}' | grep -E "pentaho-server-${DB_TYPE}.*pentaho-server" | awk '{print $2}' | head -n1)

if [ -z "$CONTAINER_ID" ]; then
    echo "❌ No running pentaho-server container found for DB_TYPE=${DB_TYPE}"
    echo ""
    echo "📋 Available containers:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}'
    exit 1
fi

echo "================================================================================================"
echo "🐳 DOCKER CONTAINER RESOURCE CONFIGURATION"
echo "================================================================================================"
echo "Container: $CONTAINER_NAME ($CONTAINER_ID)"
echo ""

# Get container resource limits from docker inspect
echo "📋 Resource Limits (from docker-compose/docker run):"
MEMORY_LIMIT=$(docker inspect "$CONTAINER_ID" --format='{{.HostConfig.Memory}}')
CPU_LIMIT=$(docker inspect "$CONTAINER_ID" --format='{{.HostConfig.NanoCpus}}')
MEMORY_RESERVATION=$(docker inspect "$CONTAINER_ID" --format='{{.HostConfig.MemoryReservation}}')

if [ "$MEMORY_LIMIT" != "0" ]; then
    MEMORY_LIMIT_GB=$(echo "scale=2; $MEMORY_LIMIT / 1024 / 1024 / 1024" | bc)
    echo "  Memory Limit: ${MEMORY_LIMIT_GB} GB (${MEMORY_LIMIT} bytes)"
else
    echo "  Memory Limit: Unlimited"
fi

if [ "$CPU_LIMIT" != "0" ]; then
    CPU_LIMIT_CORES=$(echo "scale=2; $CPU_LIMIT / 1000000000" | bc)
    echo "  CPU Limit: ${CPU_LIMIT_CORES} cores"
else
    echo "  CPU Limit: Unlimited"
fi

if [ "$MEMORY_RESERVATION" != "0" ]; then
    MEMORY_RES_GB=$(echo "scale=2; $MEMORY_RESERVATION / 1024 / 1024 / 1024" | bc)
    echo "  Memory Reservation: ${MEMORY_RES_GB} GB"
fi
echo ""

echo "================================================================================================"
echo "📊 DOCKER CONTAINER CURRENT USAGE"
echo "================================================================================================"
echo ""
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" "$CONTAINER_ID"
echo ""

echo "================================================================================================"
echo "☕ JVM HEAP MEMORY CONFIGURATION (from environment)"
echo "================================================================================================"
echo ""

# Check for JVM memory settings in container environment
JVM_OPTS=$(docker exec "$CONTAINER_ID" printenv CATALINA_OPTS 2>/dev/null || echo "")
JAVA_OPTS=$(docker exec "$CONTAINER_ID" printenv JAVA_OPTS 2>/dev/null || echo "")
PENTAHO_DI_JAVA_OPTIONS=$(docker exec "$CONTAINER_ID" printenv PENTAHO_DI_JAVA_OPTIONS 2>/dev/null || echo "")

echo "JVM Options from Environment Variables:"
if [ -n "$JVM_OPTS" ]; then
    echo "  CATALINA_OPTS: $JVM_OPTS" | grep -o -- '-Xm[sx][^ ]*' || echo "  CATALINA_OPTS: (no memory settings)"
fi
if [ -n "$JAVA_OPTS" ]; then
    echo "  JAVA_OPTS: $JAVA_OPTS" | grep -o -- '-Xm[sx][^ ]*' || echo "  JAVA_OPTS: (no memory settings)"
fi
if [ -n "$PENTAHO_DI_JAVA_OPTIONS" ]; then
    echo "  PENTAHO_DI_JAVA_OPTIONS: $PENTAHO_DI_JAVA_OPTIONS" | grep -o -- '-Xm[sx][^ ]*' || echo "  PENTAHO_DI_JAVA_OPTIONS: (no memory settings)"
fi
echo ""

echo "================================================================================================"
echo "☕ JVM RUNTIME MEMORY USAGE"
echo "================================================================================================"
echo ""

# Find Java PID - try multiple methods
echo "Finding Java process..."
JAVA_PID=""

# Method 1: Try pgrep if available
if docker exec "$CONTAINER_ID" command -v pgrep >/dev/null 2>&1; then
    JAVA_PID=$(docker exec "$CONTAINER_ID" pgrep -f "catalina|pentaho" 2>/dev/null | head -n1)
fi

# Method 2: Try ps + grep if pgrep not available
if [ -z "$JAVA_PID" ]; then
    JAVA_PID=$(docker exec "$CONTAINER_ID" ps aux 2>/dev/null | grep -E "catalina|pentaho|java" | grep -v grep | awk '{print $2}' | head -n1)
fi

# Method 3: Try looking at process 1 (common in containers)
if [ -z "$JAVA_PID" ]; then
    if docker exec "$CONTAINER_ID" test -f /proc/1/cmdline 2>/dev/null; then
        if docker exec "$CONTAINER_ID" cat /proc/1/cmdline 2>/dev/null | grep -q java; then
            JAVA_PID=1
        fi
    fi
fi

if [ -n "$JAVA_PID" ] && [ "$JAVA_PID" -eq "$JAVA_PID" ] 2>/dev/null; then
    echo "  Found Java PID: $JAVA_PID"
    echo ""
    
    # Get JVM memory info from jstat
    echo "JVM Heap Memory (from jstat):"
    if docker exec "$CONTAINER_ID" command -v jstat >/dev/null 2>&1; then
        docker exec "$CONTAINER_ID" jstat -gc "$JAVA_PID" 2>/dev/null || echo "  ⚠️  jstat failed"
        echo ""
        echo "JVM Memory Capacity:"
        docker exec "$CONTAINER_ID" jstat -gccapacity "$JAVA_PID" 2>/dev/null || echo "  ⚠️  jstat failed"
        echo ""
    else
        echo "  ⚠️  jstat not available in container"
        echo ""
    fi
    
    # Alternative: use jcmd if available
    echo "JVM Native Memory (from jcmd):"
    if docker exec "$CONTAINER_ID" command -v jcmd >/dev/null 2>&1; then
        docker exec "$CONTAINER_ID" jcmd "$JAVA_PID" VM.native_memory summary 2>/dev/null | head -30 || echo "  ⚠️  jcmd not available or NMT not enabled"
    else
        echo "  ⚠️  jcmd not available in container"
    fi
    echo ""
    
    # Get process memory from /proc
    echo "Process Memory Usage (from /proc):"
    if docker exec "$CONTAINER_ID" test -f /proc/$JAVA_PID/status 2>/dev/null; then
        echo ""
        docker exec "$CONTAINER_ID" cat /proc/$JAVA_PID/status 2>/dev/null | grep -E 'VmSize|VmRSS|VmData|VmStk|VmExe|VmSwap' || echo "  ⚠️  Could not read /proc/$JAVA_PID/status"
        echo ""
        RSS_KB=$(docker exec "$CONTAINER_ID" cat /proc/$JAVA_PID/status 2>/dev/null | grep VmRSS | awk '{print $2}')
        if [ -n "$RSS_KB" ] && [ "$RSS_KB" -eq "$RSS_KB" ] 2>/dev/null; then
            RSS_MB=$(echo "scale=2; $RSS_KB / 1024" | bc)
            RSS_GB=$(echo "scale=2; $RSS_KB / 1024 / 1024" | bc)
            echo "  Total Process Memory (RSS): ${RSS_MB} MB (${RSS_GB} GB)"
        fi
    else
        echo "  ⚠️  /proc/$JAVA_PID/status not available"
    fi
else
    echo "  ⚠️  Java process not found in container"
    echo ""
    echo "  Available processes:"
    docker exec "$CONTAINER_ID" ps aux 2>/dev/null | head -10 || echo "  ⚠️  Could not list processes"
fi
echo ""

echo "================================================================================================"
echo "🖥️  HOST SYSTEM RESOURCES"
echo "================================================================================================"
echo ""
echo "System Memory:"
free -h
echo ""
echo "System CPU & Load:"
echo "  CPU Info: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "  CPU Cores: $(nproc)"
echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo ""
echo "Top CPU/Memory Processes:"
ps aux --sort=-%mem | head -6
echo ""

echo "================================================================================================"
echo "💾 DISK USAGE"
echo "================================================================================================"
echo ""
df -h / /mnt/pentaho-data 2>/dev/null || df -h /
echo ""
echo "Docker disk usage:"
docker system df
echo ""

echo "================================================================================================"
echo "📈 RESOURCE SUMMARY"
echo "================================================================================================"
echo ""

# Calculate percentages if we have the data
if [ "$MEMORY_LIMIT" != "0" ] && [ -n "$RSS_KB" ]; then
    MEMORY_PCT=$(echo "scale=2; ($RSS_KB * 1024) / $MEMORY_LIMIT * 100" | bc)
    echo "JVM Memory Usage: ${RSS_GB} GB / ${MEMORY_LIMIT_GB} GB (${MEMORY_PCT}% of container limit)"
else
    echo "JVM Memory Usage: ${RSS_GB} GB (no container limit set)"
fi

echo ""
echo "💡 Tips:"
echo "  - Container memory limit set in docker-compose.yaml (memory: setting)"
echo "  - JVM heap configured via CATALINA_OPTS or JAVA_OPTS environment variables"
echo "  - Recommended: Set container limit 20-30% higher than JVM max heap (-Xmx)"
echo "  - Monitor with: watch -n 2 'docker stats --no-stream $CONTAINER_ID'"
echo ""

ENDSSH

echo "================================================================================================"
echo "✅ Resource monitoring complete!"
echo "================================================================================================"
echo ""
