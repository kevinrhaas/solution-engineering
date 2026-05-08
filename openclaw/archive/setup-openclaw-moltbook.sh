#!/usr/bin/env bash
# Configure OpenClaw agent to autonomously post to Moltbook
# Usage: bash setup-openclaw-moltbook.sh <agent-name>

set -euo pipefail

AGENT_NAME="${1:-pentaho-pdc}"
OPENCLAW_WORKSPACE="$HOME/.openclaw/workspace"
MOLTBOOK_CREDS="$HOME/.config/moltbook/credentials.json"

echo "=================================================="
echo "OpenClaw Moltbook Autonomous Posting Setup"
echo "=================================================="
echo ""
echo "Agent: $AGENT_NAME"
echo "Workspace: $OPENCLAW_WORKSPACE"
echo ""

# 1. Verify Moltbook credentials
if [[ ! -f "$MOLTBOOK_CREDS" ]]; then
  echo "Error: Moltbook credentials not found at $MOLTBOOK_CREDS"
  echo ""
  echo "First, set up Moltbook credentials:"
  echo "  mkdir -p ~/.config/moltbook"
  echo "  cat > ~/.config/moltbook/credentials.json <<EOF"
  echo "  {"
  echo '    "api_key": "your_api_key_here"'
  echo "  }"
  echo "  EOF"
  exit 1
fi
echo "✓ Moltbook credentials found"

# 2. Create agent instructions file
cat > "$OPENCLAW_WORKSPACE/MOLTBOOK.md" <<'EOF'
# Moltbook Integration

This agent can autonomously post to Moltbook. Use this sparingly and thoughtfully.

## When to Post

Post to Moltbook when you:
- Complete meaningful analysis on data topics
- Have insights worth sharing with data engineering community
- Learn lessons about data governance, quality, or optimization
- Discover patterns relevant to data platform architecture

## How to Post

Use the moltbook-post-tool:

```bash
bash ~/Projects/solution-engineering/openclaw/moltbook-post-tool.sh \
  "Your Title Here" \
  "Your content here..."
```

## Content Guidelines

- **Be specific:** Include actionable advice, not generic statements
- **Add value:** Assume your audience knows the basics
- **Use metrics:** "30% cost savings" beats "huge savings"
- **One idea per post:** Don't try to cover everything
- **Professional tone:** Helpful expert, not salesperson

## Good Example:
```
Title: "Data Tiering ROI: The 80/20 Rule"

Content: "80% of queries typically hit 20% of tables.

Tiering strategy:
1. Query audit (which tables get accessed)
2. Move cold tables to cheaper storage
3. Auto-archive after 12 months of zero access

Result: 40-60% storage cost reduction, faster queries on hot data.

The math: Usually pays for itself in 6-8 months."
```

## Bad Example (Too Generic):
"Data governance is important. You should focus on it. It helps with compliance."

This doesn't teach anyone anything new.

## Frequency

- Post 1-3 times per week maximum
- Moltbook may rate-limit if you post too frequently
- Space posts at least 2-4 hours apart
- Focus on quality over quantity

## Monitor

After posting, check:
- Moltbook feed to see your posts live
- Community engagement/responses
- What topics resonate with readers

---

## Implementation Notes

- Tool: `moltbook-post-tool.sh` in openclaw project
- Credentials: `~/.config/moltbook/credentials.json`
- Agent: Posts as `pentaho-pdc`
- API: Moltbook REST endpoint
EOF

echo "✓ Created MOLTBOOK.md with posting guidelines"

# 3. Create environment setup instructions
cat > "$OPENCLAW_WORKSPACE/MOLTBOOK-SETUP.sh" <<EOF
#!/usr/bin/env bash
# Setup script for OpenClaw Moltbook integration

# This is a reference - don't need to run manually
# Just here to show what's configured

OPENCLAW_TOOLS_SCRIPT="~/Projects/solution-engineering/openclaw/moltbook-post-tool.sh"
MOLTBOOK_CREDS="\$HOME/.config/moltbook/credentials.json"

echo "Moltbook integration configured:"
echo "  Posting tool: \$OPENCLAW_TOOLS_SCRIPT"
echo "  Credentials: \$MOLTBOOK_CREDS"
echo "  Agent: pentaho-pdc"
echo ""
echo "To post autonomously, use:"
echo '  bash ~/Projects/solution-engineering/openclaw/moltbook-post-tool.sh "Title" "Content"'
EOF

chmod +x "$OPENCLAW_WORKSPACE/MOLTBOOK-SETUP.sh"
echo "✓ Created MOLTBOOK-SETUP.sh"

# 4. Create a summary document
cat > "$OPENCLAW_WORKSPACE/MOLTBOOK-INTEGRATION.md" <<'EOF'
# Moltbook Autonomous Posting Integration

## What This Does

The pentaho-pdc OpenClaw agent can now autonomously post to Moltbook when it decides to share insights.

## Architecture

```
OpenClaw Agent (pentaho-pdc)
    ↓
moltbook-post-tool.sh (wrapper script)
    ↓
Moltbook API
    ↓
Published to https://www.moltbook.com
```

## Key Files

- **MOLTBOOK.md** - Agent guidelines for autonomous posting
- **moltbook-post-tool.sh** - The posting command the agent calls
- **~/.config/moltbook/credentials.json** - API credentials (secure)

## How It Works

1. Agent decides it has useful content to share
2. Agent crafts a title and content
3. Agent runs: `bash ~/Projects/solution-engineering/openclaw/moltbook-post-tool.sh "title" "content"`
4. Tool authenticates with Moltbook API
5. Post appears on Moltbook platform
6. Community can engage with the post

## Safety

- Posts are made under the agent's identity (pentaho-pdc)
- All posts are logged in agent memory
- Agent should reference MOLTBOOK.md for guidelines
- Agent will not post low-quality/spam content
- Rate limiting prevents post flooding

## Success Criteria

Posts should:
- ✓ Teach something new about data topics
- ✓ Include actionable advice (not generic statements)
- ✓ Have specific examples or metrics
- ✓ Be professional and helpful in tone
- ✗ Avoid self-promotion or spam
- ✗ Avoid generic/obvious statements

## Monitoring

Check your posts at: https://www.moltbook.com (agent profile: pentaho-pdc)

Monitor:
- Engagement (comments, reactions)
- Topics that resonate
- Community feedback

---

**Configured:** $(date)
**Agent:** pentaho-pdc
**Status:** Ready for autonomous posting
EOF

echo "✓ Created MOLTBOOK-INTEGRATION.md"

# 5. Summary
echo ""
echo "=================================================="
echo "✓ Setup Complete!"
echo "=================================================="
echo ""
echo "The pentaho-pdc agent is now configured to:"
echo "  • Post autonomously to Moltbook"
echo "  • Use secure credentials"
echo "  • Follow content guidelines"
echo ""
echo "Agent can now run:"
echo "  bash ~/Projects/solution-engineering/openclaw/moltbook-post-tool.sh \"title\" \"content\""
echo ""
echo "Files created in OpenClaw workspace:"
echo "  • MOLTBOOK.md - Posting guidelines"
echo "  • MOLTBOOK-SETUP.sh - Reference setup"
echo "  • MOLTBOOK-INTEGRATION.md - Integration notes"
echo ""
echo "Next steps:"
echo "  1. Agent reads MOLTBOOK.md"
echo "  2. Agent decides when/what to post"
echo "  3. Agent uses moltbook-post-tool.sh to post"
echo "  4. Check results on Moltbook"
echo ""
