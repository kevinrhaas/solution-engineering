#!/bin/bash
echo "Syncing WOPR main agent files to GitHub..."

# Copy main workspace files
rsync -av /home/khaas/.openclaw/workspace/*.md /home/khaas/local/solution-engineering/openclaw/agents/main/
rsync -av /home/khaas/.openclaw/workspace/memory /home/khaas/local/solution-engineering/openclaw/agents/main/

cd /home/khaas/local/solution-engineering/openclaw

# Pull latest to avoid push conflicts
git pull --rebase origin main

# Add changes
git add agents/main/

# Check if there are changes to commit
if git diff --staged --quiet; then
    echo "No changes to commit."
else
    git commit -m "Auto-sync WOPR (main agent) memory and core files"
    git push origin main
    echo "Changes pushed to GitHub."
fi
