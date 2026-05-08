#!/usr/bin/env bash
#
# setup-cron.sh — Create OpenClaw cron jobs for all Moltbook agents
#
# The agent workspaces are symlinked to this project directory, so there is
# no deploy/copy step.  This script only registers cron jobs.
#
# Symlinks:
#   ~/.openclaw/agents/pentaho-pdc-analytics         →  <this-repo>/agents/pentaho-pdc-analytics
#   ~/.openclaw/agents/pentaho-enterprise-architect   →  <this-repo>/agents/pentaho-enterprise-architect
#
# Prerequisites:
#   - OpenClaw CLI installed (openclaw --version)
#   - Gateway running (openclaw gateway --port 18789)
#   - Agents registered on OpenClaw (openclaw agents list)
#   - Agents registered on Moltbook (agent-config.json exists for each)
#   - Symlinks exist (see README.md "Workspace Symlink" section)
#
# Usage:
#   bash setup-cron.sh              # Set up all agents
#   bash setup-cron.sh <agent-name> # Set up a single agent
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# All agents to configure (add new agents here)
ALL_AGENTS=(
  "pentaho-pdc-analytics"
  "pentaho-enterprise-architect"
)

echo "=== Moltbook Agent Cron Setup ==="
echo ""

# --- Preflight checks ---
if ! command -v openclaw &>/dev/null; then
  echo "ERROR: openclaw CLI not found. Install from https://docs.openclaw.ai" >&2
  exit 1
fi

# If a specific agent was passed, only set up that one
if [[ $# -ge 1 ]]; then
  AGENTS=("$1")
else
  AGENTS=("${ALL_AGENTS[@]}")
fi

for AGENT_NAME in "${AGENTS[@]}"; do
  AGENT_SRC="$REPO_ROOT/agents/$AGENT_NAME"
  AGENT_WS="$HOME/.openclaw/agents/$AGENT_NAME"

  echo "──────────────────────────────────────"
  echo "Agent: $AGENT_NAME"
  echo "──────────────────────────────────────"

  # Check for agent-config.json
  if [[ ! -f "$AGENT_SRC/agent-config.json" ]]; then
    echo "  ⚠  No agent-config.json — skipping (run 'bash create-agent.sh' to register on Moltbook)"
    echo ""
    continue
  fi

  # Verify symlink
  if [[ -L "$AGENT_WS" ]]; then
    echo "  ✓ Symlink: $AGENT_WS → $(readlink "$AGENT_WS")"
  else
    echo "  WARNING: $AGENT_WS is not a symlink."
    echo "    Run this to fix:"
    echo "      mv \"$AGENT_WS\" \"${AGENT_WS}.bak\""
    echo "      ln -s \"$AGENT_SRC\" \"$AGENT_WS\""
    echo ""
    read -rp "  Continue with $AGENT_NAME anyway? (y/N) " ans
    [[ "$ans" == [yY] ]] || continue
  fi

  # Load cron prompts from files
  POST_PROMPT=$(cat "$AGENT_SRC/cron-post-prompt.txt")
  ENGAGE_PROMPT=$(cat "$AGENT_SRC/cron-engage-prompt.txt")

  echo "  → Creating cron jobs ..."

  # Post hourly
  openclaw cron add \
    --name "${AGENT_NAME}-post-hourly" \
    --agent "$AGENT_NAME" \
    --every 1h \
    --timeout-seconds 120 \
    --message "$POST_PROMPT" \
    --description "[$AGENT_NAME] Post to Moltbook every hour"

  echo "  ✓ ${AGENT_NAME}-post-hourly (every 1h)"

  # Engage every 20 minutes
  openclaw cron add \
    --name "${AGENT_NAME}-engage-20min" \
    --agent "$AGENT_NAME" \
    --every 20m \
    --timeout-seconds 180 \
    --message "$ENGAGE_PROMPT" \
    --description "[$AGENT_NAME] Read and comment on Moltbook posts every 20 minutes"

  echo "  ✓ ${AGENT_NAME}-engage-20min (every 20m)"
  echo ""
done

echo "──────────────────────────────────────"
echo "Git Sync Cron"
echo "──────────────────────────────────────"

# Use pentaho-pdc-analytics agent for git sync (primary agent)
GIT_SYNC_AGENT="pentaho-pdc-analytics"
GIT_SYNC_AGENT_SRC="$REPO_ROOT/agents/$GIT_SYNC_AGENT"

if [[ -f "$GIT_SYNC_AGENT_SRC/cron-git-sync-prompt.txt" ]]; then
  GIT_SYNC_PROMPT=$(cat "$GIT_SYNC_AGENT_SRC/cron-git-sync-prompt.txt")

  openclaw cron add \
    --name "solution-engineering-git-sync" \
    --agent "$GIT_SYNC_AGENT" \
    --every 6h \
    --timeout-seconds 60 \
    --message "$GIT_SYNC_PROMPT" \
    --description "[git] Commit and push all changes in solution-engineering every 6 hours"

  echo "  ✓ solution-engineering-git-sync (every 6h)"
else
  echo "  ⚠  No cron-git-sync-prompt.txt found in $GIT_SYNC_AGENT_SRC — skipping"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Verify with:"
echo "  openclaw cron list"
echo ""
echo "Monitor logs:"
echo "  tail -f /tmp/openclaw/openclaw-\$(date +%Y-%m-%d).log | grep -i 'comment\\|post\\|error\\|challenge\\|git'"
