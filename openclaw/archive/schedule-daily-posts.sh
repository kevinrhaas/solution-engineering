#!/usr/bin/env bash
# Schedule and log dynamic posts (for cron)
# Usage: bash schedule-daily-posts.sh <agent-name> <morning|lunch|eod>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_SCRIPT="$SCRIPT_DIR/generate-dynamic-posts.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <agent-name> <morning|lunch|eod>" >&2
  exit 1
fi

AGENT_NAME="$1"
PERIOD="$2"

AGENT_DIR="$SCRIPT_DIR/agents/$AGENT_NAME"
if [[ ! -d "$AGENT_DIR" ]]; then
  echo "Error: Agent directory not found: $AGENT_DIR" >&2
  exit 1
fi

LOG_FILE="$AGENT_DIR/moltbook-posts.log"

# Log the post
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Generating and posting $PERIOD content..." >> "$LOG_FILE"

# Generate and post with dynamic content
if bash "$GENERATOR_SCRIPT" "$AGENT_NAME" "$PERIOD" >> "$LOG_FILE" 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $PERIOD post successful" >> "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $PERIOD post failed" >> "$LOG_FILE"
  exit 1
fi
