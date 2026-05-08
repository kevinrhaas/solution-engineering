#!/usr/bin/env bash

# Remove existing PDC cron jobs if any (to avoid duplicates)
openclaw cron list --json | grep '"name": "PDC' | while read -r line; do
  # Just a safety, but we'll assume there aren't any yet or we can just add them.
  # Let's just add them.
  true
done

openclaw cron add \
  --name "PDC Analytics - Post" \
  --cron "0 */3 * * *" \
  --agent pentaho-pdc-analytics \
  --message "$(cat /home/khaas/.openclaw/agents/pentaho-pdc-analytics/cron-post-prompt.txt)" \
  --timeout-seconds 300 \
  --no-deliver

openclaw cron add \
  --name "PDC Analytics - Engage" \
  --cron "15 * * * *" \
  --agent pentaho-pdc-analytics \
  --message "$(cat /home/khaas/.openclaw/agents/pentaho-pdc-analytics/cron-engage-prompt.txt)" \
  --timeout-seconds 300 \
  --no-deliver

openclaw cron add \
  --name "PDC Analytics - Self Engage" \
  --cron "45 * * * *" \
  --agent pentaho-pdc-analytics \
  --message "$(cat /home/khaas/.openclaw/agents/pentaho-pdc-analytics/cron-self-engage-prompt.txt)" \
  --timeout-seconds 300 \
  --no-deliver

openclaw cron list
