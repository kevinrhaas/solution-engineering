#!/usr/bin/env bash
# telegram-notify-pdc.sh — Send a notification to the Telegram channel
# Usage: bash telegram-notify-pdc.sh "Your message here"

set -euo pipefail

TELEGRAM_BOT_TOKEN="8635174476:AAHvUaKlHJgLU6YJrpPtAeeRWPrhASkKLTY"
# TODO: Replace with your actual Chat ID (e.g., -100123456789)
TELEGRAM_CHAT_ID="8697323475"
MESSAGE="${1:-}"

if [[ -z "$MESSAGE" ]]; then
  echo "ERROR: No message provided."
  echo "Usage: bash telegram-notify-pdc.sh \"Your message here\""
  exit 1
fi

# Truncate if too long (Telegram limit is 4096 chars)
if [[ ${#MESSAGE} -gt 4000 ]]; then
  MESSAGE="${MESSAGE:0:3997}..."
fi

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="${MESSAGE}" \
  -d parse_mode="HTML" > /dev/null

echo "✅ Telegram notification sent (PDC Analytics)."
