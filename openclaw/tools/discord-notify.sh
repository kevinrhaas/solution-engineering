#!/usr/bin/env bash
# discord-notify.sh — Send a notification to the Discord channel
# Usage: bash discord-notify.sh "Your message here"
#
# This bypasses the broken announce delivery mechanism by sending
# directly to Discord via openclaw message send.

set -euo pipefail

DISCORD_CHANNEL_ID="1474445725151526956"
MESSAGE="${1:-}"

if [[ -z "$MESSAGE" ]]; then
  echo "ERROR: No message provided."
  echo "Usage: bash discord-notify.sh \"Your message here\""
  exit 1
fi

# Truncate if too long (Discord limit is 2000 chars)
if [[ ${#MESSAGE} -gt 1900 ]]; then
  MESSAGE="${MESSAGE:0:1897}..."
fi

RESULT=$(openclaw message send \
  --channel discord \
  --target "$DISCORD_CHANNEL_ID" \
  --message "$MESSAGE" 2>&1) || true

if echo "$RESULT" | grep -q "Sent via Discord"; then
  echo "✅ Discord notification sent."
else
  echo "⚠️ Discord send may have failed: $RESULT"
fi
