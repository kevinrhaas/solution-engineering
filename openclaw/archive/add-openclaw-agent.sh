#!/usr/bin/env bash
# Create an agent in OpenClaw and Moltbook
# Usage: bash add-openclaw-agent.sh <agent-name>

set -euo pipefail

AGENT_NAME="${1:-}"

if [[ -z "$AGENT_NAME" ]]; then
  echo "Usage: $0 <agent-name>"
  echo "Example: $0 pentaho-pdc-analytics"
  exit 1
fi

OPENCLAW_DIR="$HOME/.openclaw/agents"

# Create in OpenClaw
echo "Creating agent in OpenClaw..."
mkdir -p "$OPENCLAW_DIR/$AGENT_NAME/sessions"
echo "✓ Agent created: $OPENCLAW_DIR/$AGENT_NAME"

# Register with our system
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/register-with-openclaw.sh" "http://127.0.0.1:18789" "$AGENT_NAME"

echo ""
echo "✅ Complete! Now:"
echo "  1. Refresh OpenClaw dashboard in browser"
echo "  2. You should see '$AGENT_NAME' in the Agents list"
