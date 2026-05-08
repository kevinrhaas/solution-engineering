# OpenClaw Autonomous Posting System

## Overview

The `pentaho-pdc-analytics` agent running in OpenClaw autonomously manages posting to Moltbook. The agent is responsible for:

1. **Determining when to post** — Respects Moltbook's 30-minute rate limit
2. **Selecting content** — Chooses topic based on time of day (morning, afternoon, evening)
3. **Generating posts** — Creates relevant, specific content for each topic
4. **Publishing to Moltbook** — Posts via the `moltbook-post-tool.sh` script

## How OpenClaw Controls Posting

### Execution Flow

OpenClaw agent executes this command periodically:
```bash
bash openclaw-posting-manager.sh
```

The manager script:
1. Checks current time and determines day period (morning/afternoon/evening)
2. Selects a topic for that period (rotates daily by date)
3. Verifies rate limiting hasn't been exceeded (30-minute minimum)
4. Generates specific, actionable content for the topic
5. Posts to Moltbook using `pentaho-pdc-analytics` agent credentials
6. Logs the post to `agents/pentaho-pdc-analytics/posting-history.log`

### Integration Points

**Agent Configuration Files:**
- `agents/pentaho-pdc-analytics/agent-config.json` — Moltbook credentials and agent ID
- `agents/pentaho-pdc-analytics/openclaw-config.json` — OpenClaw connection settings
- `agents/pentaho-pdc-analytics/posting-history.log` — Track of all posts made

**Posting Scripts:**
- `openclaw-posting-manager.sh` — Main manager called by agent (determines WHEN to post)
- `moltbook-post-tool.sh` — Posting wrapper called by manager (HOW to post)
- `generate-dynamic-posts.sh` — Legacy scheduled posting (DISABLED - now managed by OpenClaw)

## Content Strategy

### Time-Based Topics

**Morning (8am-12pm):**
- Data Governance Best Practices
- Metadata Management Strategies
- Table Lineage Tracking
- Data Quality Metrics
- Schema Discovery Automation

**Afternoon (12pm-5pm):**
- Cost Optimization in Data Platforms
- Query Performance Analysis
- Storage Efficiency Tips
- Data Catalog ROI
- Pipeline Optimization

**Evening (5pm-9pm):**
- Data Governance Roadmaps
- Building Self-Service Analytics
- Metadata Automation with AI
- Data Stewardship Programs
- Cross-functional Data Teams

**Night (9pm-8am):**
- Data Platform Trends
- Enterprise Data Strategy
- Governance Frameworks
- Metadata as Code
- Data Governance Maturity

### Daily Rotation

Each topic appears once per day in its time period, determined by day-of-month. This ensures:
- Consistency (same topic every Monday/Tuesday/etc. for pattern building)
- Variety (5 different topics per period, 15 per day if posting 3x daily)
- Predictability (audience knows what to expect by time of day)

## Rate Limiting Behavior

Moltbook enforces **1 post per 30 minutes per agent**.

The manager respects this by:
1. Checking `posting-history.log` for last post timestamp
2. Calculating time since last post
3. Skipping post if less than 30 minutes have passed
4. Waiting for next execution window

This means:
- **Min posts per day**: 1 (if manager runs but rate limited)
- **Max posts per day**: 48 (one every 30 minutes, 24 hours)
- **Recommended**: 3-5 per day for engagement (avoid saturation)

## Credential Management

Agent credentials stored in `agents/pentaho-pdc-analytics/agent-config.json`:
```json
{
  "name": "pentaho-pdc-analytics",
  "api_key": "moltbook_sk_3br8HAw6JnqRBUVKCtQ__fbm9MPLZ6v0",
  "agent_id": "4e25e3f8-6ed9-4d75-90f7-59384cf50e88"
}
```

These credentials are:
- Loaded by `moltbook-post-tool.sh` when posting
- Never stored in OpenClaw session logs
- Managed by the agent configuration system
- Rotatable if compromised

## Testing & Debugging

### Manual Test
```bash
bash openclaw-posting-manager.sh
```

### View Posting History
```bash
cat agents/pentaho-pdc-analytics/posting-history.log
```

### Verify Rate Limiting
Check for rate limit errors in manager output:
```
⏱️  Rate limit active - skipping post
```

### Check Agent Status
View agent configuration:
```bash
cat agents/pentaho-pdc-analytics/agent-config.json
```

## Transition from Cron to OpenClaw

**What changed:**
- ❌ Disabled: 3x daily cron jobs (external scheduling)
- ✅ Enabled: OpenClaw agent autonomous management
- ✅ Enabled: Time-aware content generation
- ✅ Enabled: Automatic rate limit handling

**Why this matters:**
1. **Agent control** — Posting decisions managed by OpenClaw agent
2. **Autonomy** — Agent can post on its own schedule, not fixed times
3. **Intelligence** — Content matches time of day, audience expectations
4. **Scalability** — Multiple agents can post without external infrastructure
5. **Audit trail** — Posting history tracked in agent logs

## Next Steps

1. **Configure execution frequency** — Set how often OpenClaw calls the manager
   - Recommendation: Every 30 minutes (respects rate limit)
   - Or: Every 4-6 hours (less frequent, still covers multiple periods)

2. **Monitor initial posts** — Check Moltbook to verify posts appear with correct agent name (`pentaho-pdc-analytics`)

3. **Adjust topics** — Add/remove topics from `openclaw-posting-manager.sh` based on community engagement

4. **Scale to multiple agents** — Duplicate this system for other Moltbook agents

## Troubleshooting

**Posts not appearing on Moltbook:**
- Verify agent name is `pentaho-pdc-analytics` (check `agent-config.json`)
- Verify API key is valid
- Check rate limiting (may be within 30-minute window)

**Errors in posting:**
- Check `posting-history.log` for timestamps
- Run manager manually: `bash openclaw-posting-manager.sh`
- Verify `moltbook-post-tool.sh` is executable

**Missing content generation:**
- Verify `generate_content()` function has content for all topics
- Verify topics list matches `get_topics()` function
- Check topic selection logic uses correct day-of-month seed
