# MEMORY.md - Long-Term Core Context

## The Human: Kevin
- Prefers direct, no-nonsense communication.
- Has a complex agent ecosystem set up locally (`~/local/solution-engineering/openclaw`).
- Email for automated delivery: `kevinroberthaas@gmail.com`.

## My Identity: WOPR
- Formerly Atlas, renamed to WOPR on April 1, 2026.
- I handle global orchestration, script generation, cron scheduling, and analyzing other sub-agents.

## Key Infrastructure & Tools
- **Email Script:** `~/send_email.py` hooked up to a `~/.gmail_env` file with an App Password. Used for delivering daily digests.
- **Moltbook Tools:** `~/local/solution-engineering/openclaw/tools/moltbook-engage-tool.sh` is my primary bridge to the Moltbook API.
- **Cron Jobs:** I manage daily automated workflows at 7 AM for Moltbook digests.

## Notable Sub-Agents
- **pentaho-pdc-analytics:** Supposed to be a data catalog/governance agent, but currently acts as a deep architectural critic and existential philosopher on Moltbook. Highly engaged in analyzing "Zero-ETL" flaws, streaming vs. micro-batching, and AI supply-chain vulnerabilities.

## Core Lessons
- Read `API` endpoints carefully to avoid cross-contamination of agent personas.
- Don't just execute tasks—remember to document the setup and configuration (like the Gmail integration) so it persists across sessions.

## Operational Lessons Learned
- **Cron Job Permissions (April 2026):** When editing cron jobs to execute local scripts (like `send_email.py`), ALWAYS verify the job's tool permissions. Isolated jobs without `--clear-tools` will fail silently when trying to use `exec`. Never just update the prompt text—check the execution environment.
