#!/bin/bash

# ================================================================================================
# Comprehensive Container Diagnostics
# ================================================================================================
# Diagnoses container failures, exits, crashes, and disappearances by checking:
#   - Container status and exit reasons
#   - Docker daemon and system logs
#   - Historical events (docker events, journalctl, dmesg)
#   - Resource exhaustion (OOM, disk, memory)
#   - Container configuration (limits, restart policies)
#   - Cgroups and kernel messages
# 
# Usage: ./98-diagnose-container.sh <env-file> [db-type]
# Example: ./98-diagnose-container.sh pentaho-deployment-sample-11-1-0-0-120.env
# Example: ./98-diagnose-container.sh pentaho-deployment-sample-11-1-0-0-120.env mysql
# ================================================================================================

if [ $# -lt 1 ]; then
    echo "Usage: $0 <env-file> [db-type]"
    echo ""
    echo "Arguments:"
    echo "  env-file  - Required. Environment file (e.g., pentaho-deployment-sample-11-1-0-0-120.env)"
    echo "  db-type   - Optional. Database type (postgres, mysql, sqlserver, oracle). Default: postgres"
    echo ""
    echo "Examples:"
    echo "  $0 pentaho-deployment-sample-11-1-0-0-120.env                # Diagnose default postgres container"
    echo "  $0 pentaho-deployment-sample-11-1-0-0-120.env mysql          # Diagnose mysql container"
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
echo "🔍 Comprehensive Container Diagnostics"
echo "================================================================================================"
echo "Environment:    ${ENVIRONMENT}"
echo "EC2 Instance:   ${INSTANCE_ID} (${SSH_IP})"
echo "Database Type:  ${DB_TYPE}"
echo "Container:      pentaho-server-${DB_TYPE}-pentaho-server"
echo "================================================================================================"
echo ""

ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_IP} "export DB_TYPE='${DB_TYPE}'; bash -s" <<'ENDSSH'
set -e

# Find pentaho-server container
CONTAINER_ID=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep -E "pentaho-server-${DB_TYPE}.*pentaho-server" | awk '{print $1}' | head -n1)
CONTAINER_NAME=$(docker ps -a --format '{{.ID}} {{.Names}}' | grep -E "pentaho-server-${DB_TYPE}.*pentaho-server" | awk '{print $2}' | head -n1)

echo "================================================================================================"
echo "📋 SECTION 1: CONTAINER STATUS & CURRENT STATE"
echo "================================================================================================"
echo ""

echo "🔍 All containers (running and stopped):"
docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.State}}\t{{.Status}}'
echo ""

if [ -z "$CONTAINER_ID" ]; then
    echo "⚠️  No pentaho-server container found for DB_TYPE=${DB_TYPE}"
    echo ""
    echo "Available containers:"
    docker ps -a --format 'table {{.Names}}\t{{.Status}}'
    echo ""
    echo "Skipping container-specific diagnostics..."
else
    echo "Target Container: $CONTAINER_NAME ($CONTAINER_ID)"
    echo ""
    
    echo "Container State:"
    docker inspect "$CONTAINER_ID" | grep -A 15 '"State"'
    echo ""
    
    echo "Exit Code & Error:"
    docker inspect "$CONTAINER_ID" --format='ExitCode: {{.State.ExitCode}}, Error: {{.State.Error}}, OOMKilled: {{.State.OOMKilled}}'
    echo ""
fi

echo "================================================================================================"
echo "📊 SECTION 2: SYSTEM RESOURCES"
echo "================================================================================================"
echo ""

echo "💾 Memory Usage:"
free -h
echo ""
echo "Swap:"
swapon -s 2>/dev/null || echo "No swap configured"
echo ""

echo "💿 Disk Usage:"
df -h
echo ""
echo "Largest directories:"
du -sh /* 2>/dev/null | sort -rh | head -10
echo ""

echo "🐳 Docker Disk Usage:"
docker system df
echo ""

echo "⚙️  System Load:"
uptime
echo ""
echo "CPU Info: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo ""

if [ -n "$CONTAINER_ID" ]; then
    echo "================================================================================================"
    echo "📝 SECTION 3: CONTAINER CONFIGURATION"
    echo "================================================================================================"
    echo ""
    
    echo "Restart Policy:"
    docker inspect "$CONTAINER_ID" | grep -A 5 '"RestartPolicy"'
    echo ""
    
    echo "Memory Limits:"
    MEMORY_LIMIT=$(docker inspect "$CONTAINER_ID" --format='{{.HostConfig.Memory}}')
    if [ "$MEMORY_LIMIT" != "0" ]; then
        MEMORY_LIMIT_GB=$(echo "scale=2; $MEMORY_LIMIT / 1024 / 1024 / 1024" | bc)
        echo "  Memory Limit: ${MEMORY_LIMIT_GB} GB (${MEMORY_LIMIT} bytes)"
    else
        echo "  Memory Limit: Unlimited"
    fi
    docker inspect "$CONTAINER_ID" | grep -E "MemorySwap|MemoryReservation"
    echo ""
    
    echo "CPU Limits:"
    CPU_LIMIT=$(docker inspect "$CONTAINER_ID" --format='{{.HostConfig.NanoCpus}}')
    if [ "$CPU_LIMIT" != "0" ]; then
        CPU_LIMIT_CORES=$(echo "scale=2; $CPU_LIMIT / 1000000000" | bc)
        echo "  CPU Limit: ${CPU_LIMIT_CORES} cores"
    else
        echo "  CPU Limit: Unlimited"
    fi
    docker inspect "$CONTAINER_ID" | grep -E "CpuShares|CpuQuota|CpuPeriod"
    echo ""
    
    echo "Health Check:"
    docker inspect "$CONTAINER_ID" | grep -A 10 '"HealthCheck"' || echo "  No health check configured"
    echo ""
fi

echo "================================================================================================"
echo "📜 SECTION 4: CONTAINER LOGS (Recent)"
echo "================================================================================================"
echo ""

if [ -n "$CONTAINER_ID" ]; then
    echo "Last 100 lines of container logs:"
    docker logs --tail 100 "$CONTAINER_ID" 2>&1 || echo "⚠️  Could not retrieve container logs"
else
    echo "⚠️  No container found to retrieve logs from"
fi
echo ""

echo "================================================================================================"
echo "🕒 SECTION 5: DOCKER EVENTS HISTORY"
echo "================================================================================================"
echo ""

echo "Docker events for pentaho containers (last 2 hours):"
docker events --since 2h --format '{{.Time}}\t{{.Status}}\t{{.Actor.Attributes.name}}' 2>/dev/null | grep -i pentaho || echo "⚠️  No docker events found (logs may be rotated)"
echo ""

echo "================================================================================================"
echo "📖 SECTION 6: SYSTEM LOGS - Docker Service"
echo "================================================================================================"
echo ""

echo "Docker daemon logs (last 100 lines):"
journalctl -u docker.service -n 100 --no-pager 2>/dev/null || echo "⚠️  Could not read docker.service logs"
echo ""

echo "================================================================================================"
echo "🚨 SECTION 7: KERNEL MESSAGES & OOM KILLER"
echo "================================================================================================"
echo ""

echo "OOM Killer events:"
dmesg | grep -E "Out of memory|OOM-kill|Killed process|pentaho" | tail -50 || echo "No OOM events found"
echo ""

echo "Segmentation faults:"
dmesg | grep -E "segfault" | tail -20 || echo "No segfaults found"
echo ""

echo "Recent kernel messages:"
dmesg | tail -50
echo ""

echo "================================================================================================"
echo "⚠️  SECTION 8: SYSTEM ERROR LOGS"
echo "================================================================================================"
echo ""

echo "Journalctl errors (last 100 error-level messages):"
journalctl -p err -n 100 --no-pager 2>/dev/null || echo "⚠️  Could not read error logs"
echo ""

echo "Pentaho-related errors (last 2 hours):"
journalctl --since "2 hours ago" -p err..alert --no-pager 2>/dev/null | grep -i -E "pentaho|postgres|mysql|docker" | head -50 || echo "No pentaho-related errors found"
echo ""

echo "Disk/Memory exhaustion errors:"
journalctl -n 500 --no-pager 2>/dev/null | grep -i -E "no space|disk full|cannot allocate" | tail -30 || echo "No disk/memory errors found"
echo ""

echo "================================================================================================"
echo "🏗️  SECTION 9: CGROUPS & MEMORY LIMITS"
echo "================================================================================================"
echo ""

if [ -d /sys/fs/cgroup ]; then
    echo "Cgroup entries for pentaho:"
    find /sys/fs/cgroup -name "*pentaho*" 2>/dev/null | head -10 || echo "No cgroup entries found for pentaho"
    echo ""
    
    # Check memory limit history (cgroups v1)
    if [ -f /sys/fs/cgroup/memory/docker/*/memory.max_usage_in_bytes ]; then
        echo "Memory usage history:"
        find /sys/fs/cgroup/memory/docker -name "memory.max_usage_in_bytes" -exec sh -c 'echo "$1: $(cat $1)"; cat ${1%/*}/memory.limit_in_bytes' _ {} \; 2>/dev/null | head -10
    else
        echo "Memory history not available (may be using cgroups v2)"
    fi
else
    echo "⚠️  cgroups not available"
fi
echo ""

echo "================================================================================================"
echo "⚙️  SECTION 10: DOCKER COMPOSE CONFIGURATION"
echo "================================================================================================"
echo ""

if [ -d /home/ubuntu/pentaho/onprem/dist/on-prem/pentaho-server/pentaho-server-${DB_TYPE} ]; then
    cd /home/ubuntu/pentaho/onprem/dist/on-prem/pentaho-server/pentaho-server-${DB_TYPE}
    echo "Working directory: $(pwd)"
    echo ""
    if [ -f docker-compose-${DB_TYPE}.yaml ]; then
        echo "--- docker-compose-${DB_TYPE}.yaml (relevant sections) ---"
        echo ""
        echo "Services section:"
        grep -A 30 "^services:" docker-compose-${DB_TYPE}.yaml | head -40
        echo ""
        echo "Deploy/Resources section:"
        grep -A 15 "deploy:" docker-compose-${DB_TYPE}.yaml || echo "No deploy section found"
        echo ""
        echo "Environment variables:"
        grep -A 10 "environment:" docker-compose-${DB_TYPE}.yaml || echo "No environment section found"
    else
        echo "⚠️  docker-compose-${DB_TYPE}.yaml not found"
    fi
else
    echo "⚠️  Pentaho deployment directory not found"
fi
echo ""

echo "================================================================================================"
echo "🐋 SECTION 11: DOCKER SYSTEM INFO"
echo "================================================================================================"
echo ""

docker info | grep -E "Storage Driver|Docker Root Dir|Runtimes|Operating System|Server Version|Kernel Version|Total Memory|CPUs"
echo ""

ENDSSH

echo ""
echo "================================================================================================"
echo "✅ Diagnostic Collection Complete!"
echo "================================================================================================"
echo ""
echo "💡 WHAT TO LOOK FOR:"
echo ""
echo "  🔴 Container Exited:"
echo "     - ExitCode 137 = OOMKilled (out of memory)"
echo "     - ExitCode 1 = Application error (check container logs)"
echo "     - ExitCode 143 = SIGTERM signal (graceful shutdown)"
echo "     - ExitCode 139 = Segmentation fault (SIGSEGV)"
echo ""
echo "  💾 Memory Issues:"
echo "     - Look for 'OOM-kill' or 'Out of memory' in kernel messages"
echo "     - Check if free memory < 500MB"
echo "     - Check if swap is being used heavily"
echo "     - Verify CONTAINER_MEMORY_LIMIT in env file"
echo ""
echo "  💿 Disk Issues:"
echo "     - Root (/) > 85% full = critical"
echo "     - Look for 'No space left on device' errors"
echo "     - Check Docker disk usage with 'docker system df'"
echo ""
echo "  🔧 Configuration Issues:"
echo "     - RestartPolicy 'no' = container won't auto-restart"
echo "     - Memory limit too low for JVM heap size"
echo "     - Missing health checks"
echo ""
echo "🛠️  REMEDIATION STEPS:"
echo ""
echo "  If OOM (Out of Memory):"
echo "    1. Increase CONTAINER_MEMORY_LIMIT in ${ENV_FILE_NAME}"
echo "    2. Re-run: ./10-deploy-pentaho.sh ${ENV_FILE_NAME}"
echo ""
echo "  If Disk Full:"
echo "    1. Run: ./05-grow-root-volume.sh ${ENV_FILE_NAME} 100"
echo "    2. Or: docker system prune -a"
echo ""
echo "  If Application Error:"
echo "    1. Check container logs above for stack traces"
echo "    2. Run: ./93-tail-catalina-log.sh ${ENV_FILE_NAME} for detailed logs"
echo ""
