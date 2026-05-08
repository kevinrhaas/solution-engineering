#!/usr/bin/env bash
# Configure OpenClaw iMessage notifications for posting manager
# This sets up environment variables so the posting manager sends notifications

# Get your phone number/contact for notifications
read -p "Enter your phone number for iMessage notifications (e.g., +1234567890): " PHONE_NUMBER

if [[ -z "$PHONE_NUMBER" ]]; then
  echo "No phone number provided. Notifications disabled."
  exit 1
fi

# Create/update openclaw-config.sh with notification settings
CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/openclaw-config.sh"

cat > "$CONFIG_FILE" << EOF
#!/usr/bin/env bash
# OpenClaw Posting Manager Configuration
# Automatically sourced by openclaw-posting-manager.sh

# Enable/disable iMessage notifications
export OPENCLAW_NOTIFICATION_ENABLED=true

# Phone number for iMessage notifications
export OPENCLAW_NOTIFY_TARGET="$PHONE_NUMBER"

# Optional: Set posting frequency (in minutes)
# If using with cron, comment this out
# export POSTING_FREQUENCY_MINUTES=60
EOF

chmod +x "$CONFIG_FILE"

echo "✅ Configuration saved to: $CONFIG_FILE"
echo ""
echo "Notifications will be sent to: $PHONE_NUMBER"
echo ""
echo "To disable notifications, run:"
echo "  export OPENCLAW_NOTIFICATION_ENABLED=false"
echo ""
echo "Or edit: $CONFIG_FILE"
