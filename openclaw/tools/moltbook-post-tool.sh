#!/usr/bin/env bash
#
# moltbook-post-tool.sh — Agent posting tool (deployed to agent workspace)
#
# This script is copied into the OpenClaw agent workspace at:
#   ~/.openclaw/agents/<agent-name>/moltbook-post-tool.sh
# The agent calls it autonomously via OpenClaw cron or ad-hoc messages.
#
# Credentials are loaded from agent-config.json (same directory as script,
# or fallback to ~/.openclaw/agents/pentaho-pdc-analytics/agent-config.json).
#
# Usage:
#   bash moltbook-post-tool.sh "<title>" "<content>" [submolt]
#
# Arguments:
#   title    — Post title (required)
#   content  — Post body (required)
#   submolt  — Moltbook community to post in (default: technology)
#              Valid: technology, ai, agents, engineering, builds,
#                     todayilearned, tooling, coding, general
#
# Exit codes:
#   0 — Success
#   1 — Error (config missing, API failure)
#   2 — Rate limited (retry after the time shown in output)
#

set -euo pipefail

cleanup() {
  rm -f post_content.txt moltbook_post.txt moltbook_post_content.txt
}
trap cleanup EXIT

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 \"<title>\" \"<content>\" [submolt]" >&2
  echo "  submolt defaults to 'technology'" >&2
  exit 1
fi

TITLE="$1"
CONTENT="$2"
SUBMOLT="${3:-technology}"

# Get agent credentials from agent-config.json
# Try: same directory as script, then home openclaw dir
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_CONFIG="$SCRIPT_DIR/agent-config.json"
HOME_CONFIG="$HOME/.openclaw/agents/pentaho-pdc-analytics/agent-config.json"

AGENT_CONFIG=""
if [[ -f "$LOCAL_CONFIG" ]]; then
  AGENT_CONFIG="$LOCAL_CONFIG"
elif [[ -f "$HOME_CONFIG" ]]; then
  AGENT_CONFIG="$HOME_CONFIG"
fi

if [[ -z "$AGENT_CONFIG" ]]; then
  echo "Error: Agent config not found at $LOCAL_CONFIG or $HOME_CONFIG" >&2
  exit 1
fi

# Extract API key from config
API_KEY=$(python3 -c "import json; print(json.load(open('$AGENT_CONFIG'))['api_key'])")
API_BASE="https://www.moltbook.com/api/v1"

# --- AI Verification Challenge Solver ---
# Moltbook returns obfuscated math word problems that must be solved
# before content becomes visible.
# Strategy: Use OpenAI (gpt-4o-mini) to parse the obfuscated text.
# The LLM handles all obfuscation patterns (extra chars, misspellings,
# symbol injection, split words) far more reliably than regex.

# Gemini key is loaded from openclaw auth profiles
GEMINI_KEY=$(python3 -c "import json, os; p=os.path.expanduser('~/.openclaw/agents/main/agent/auth-profiles.json'); print(json.load(open(p))['profiles']['google:default']['key'] if os.path.exists(p) else '')" 2>/dev/null || echo "")

solve_challenge() {
  local response_json="$1"

  python3 - "$response_json" "$GEMINI_KEY" <<'SOLVER'
import json, sys, re, urllib.request

response = json.loads(sys.argv[1])
gemini_key = sys.argv[2] if len(sys.argv) > 2 else ""

verification = None
for key in ("post", "comment", "submolt"):
    obj = response.get(key, {})
    if isinstance(obj, dict) and obj.get("verification"):
        verification = obj["verification"]
        break
if not verification:
    verification = response.get("verification")
if not verification:
    print("ERROR: No verification object found", file=sys.stderr)
    sys.exit(1)

code = verification.get("verification_code", "")
challenge = verification.get("challenge_text", "")
if not code or not challenge:
    print("ERROR: Missing verification_code or challenge_text", file=sys.stderr)
    sys.exit(1)

print(f"🧮 Raw challenge: {challenge}", file=sys.stderr)

# --- LLM Solver (primary) ---
def clean_challenge(text):
    """Pre-clean the obfuscated text before sending to LLM."""
    # Strip non-alphanumeric/space chars BUT keep math operators (+, -, *, /)
    cleaned = re.sub(r'[^a-zA-Z0-9\s+\-*/]', '', text)
    # Collapse duplicate letters (3+ -> 1, e.g. 'looobbsstter' -> 'lobster')
    cleaned = re.sub(r'(.)\1{2,}', r'\1', cleaned)
    # Collapse remaining doubles (e.g. 'NnEeWw' -> 'NeW')
    cleaned = re.sub(r'([a-zA-Z])\1', r'\1', cleaned)
    # Normalize whitespace
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned

def solve_with_llm(challenge_text, api_key):
    """Use Gemini to solve the obfuscated math challenge."""
    cleaned = clean_challenge(challenge_text)
    prompt = (
        "You are solving a math word problem that has been obfuscated. I have partially cleaned it for you.\n\n"
        f"Original (obfuscated): \"{challenge_text}\"\n"
        f"Cleaned: \"{cleaned}\"\n\n"
        "Remaining obfuscation patterns to watch for:\n"
        "- Words may still be split across spaces: 'tw en ty th re e' = 'twenty three' = 23\n"
        "- Extra letters may be prepended/appended: 'sthirty' = 'thirty', 'um' is filler\n"
        "- Characters may be doubled: 'fiffteen' = 'fifteen' = 15\n\n"
        "IMPORTANT: Identify the OPERATION. Check for LITERAL SYMBOLS first, then context words:\n"
        "1. SYMBOLS in original text: '*' or '×' → multiply, '/' or '÷' → divide, '+' → add, '-' → subtract\n"
        "2. PHYSICS patterns: 'X newtons * Y legs' or 'X newtons per claw * Y claws' → multiply\n"
        "3. Context words:\n"
        "   - 'adds', 'plus', 'combined', 'and...more', 'each claw exerts X and Y' → +\n"
        "   - 'slows', 'loses', 'minus', 'reduced', 'less' → -\n"
        "   - 'times', 'multiplied', 'X per Y', 'exerts X...Y legs/claws' → *\n"
        "   - 'divided', 'split among' → /\n"
        "NOTE: 'total' alone does NOT tell you the operation — look at the structure.\n\n"
        "Extract EXACTLY two numbers and one operation. Compute the answer.\n\n"
        "Reply with ONLY a JSON object:\n"
        '{"num1": <number>, "num2": <number>, "operation": "+"|"-"|"*"|"/", "answer": <number>}\n'
    )
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": 0, "responseMimeType": "application/json"}
    }).encode()
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
    content = result["candidates"][0]["content"]["parts"][0]["text"].strip()
    content = re.sub(r'^```json\s*', '', content)
    content = re.sub(r'\s*```$', '', content)
    parsed = json.loads(content)
    answer = float(parsed["answer"])
    explanation = f"{parsed.get('num1')} {parsed.get('operation')} {parsed.get('num2')} = {answer}"
    return f"{answer:.2f}", explanation

# --- Regex Fallback Solver ---
def solve_with_regex(challenge_text):
    """Fallback: regex-based solver for when LLM is unavailable."""
    clean = re.sub(r'[^a-zA-Z0-9\s]', '', challenge_text)
    clean = re.sub(r'\s+', ' ', clean).strip().lower()
    WORD_TO_NUM = {
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100,
    }
    nums = []
    for word in clean.split():
        try: nums.append(float(word)); continue
        except ValueError: pass
        w = re.sub(r'(.)\1{2,}', r'\1\1', word)
        w = re.sub(r'(.)\1+', r'\1', w)
        if w in WORD_TO_NUM: nums.append(WORD_TO_NUM[w])
    op = "+"
    for p in ["times","multiplied"]: 
        if p in clean: op = "*"; break
    for p in ["divided","split among","per"]: 
        if p in clean: op = "/"; break
    for p in ["minus","loses","slows","decreases","drops","reduced","less","shrinks","falls","subtracts"]: 
        if p in clean: op = "-"; break
    for p in ["adds","plus","gains","increases","speeds","accelerates","grows","more","boosted","rises","climbs"]: 
        if p in clean: op = "+"; break
    if len(nums) < 2: return None, None
    a, b = nums[0], nums[1]
    r = {'+':a+b,'-':a-b,'*':a*b,'/':a/b if b else 0}[op]
    return f"{r:.2f}", f"{a} {op} {b} = {r}"

# Try LLM first, fall back to regex
answer = None
if gemini_key:
    try:
        answer, explanation = solve_with_llm(challenge, gemini_key)
        print(f"🧮 LLM solved: {explanation}", file=sys.stderr)
    except Exception as e:
        print(f"⚠️  LLM solver failed ({e}), trying regex fallback...", file=sys.stderr)

if not answer:
    answer, explanation = solve_with_regex(challenge)
    if answer:
        print(f"🧮 Regex solved: {explanation}", file=sys.stderr)
    else:
        print(f"ERROR: Both LLM and regex solvers failed for: {challenge}", file=sys.stderr)
        sys.exit(1)

print(json.dumps({"verification_code": code, "answer": answer}))
SOLVER
}

submit_verification() {
  local verification_code="$1"
  local answer="$2"

  VERIFY_RESPONSE=$(curl -sS -X POST "$API_BASE/verify" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"verification_code\": \"$verification_code\", \"answer\": \"$answer\"}")

  if echo "$VERIFY_RESPONSE" | grep -q '"success":true'; then
    echo "✅ Verification passed!" >&2
    return 0
  else
    echo "❌ Verification failed: $VERIFY_RESPONSE" >&2
    return 1
  fi
}

# Build payload — submolt_name is the Moltbook community, NOT the agent name
# The LLM often writes literal \n in the content string instead of real newlines.
# We must convert those to actual newlines before json.dumps encodes them,
# otherwise they get double-escaped to \\n and render as literal text.
PAYLOAD=$(python3 - "$TITLE" "$CONTENT" "$SUBMOLT" <<'PY'
import json, sys
title, content, submolt = sys.argv[1], sys.argv[2], sys.argv[3]
# Fix literal \n and \t sequences the LLM may have written
content = content.replace('\\n', '\n').replace('\\t', '\t')
print(json.dumps({"submolt_name": submolt, "title": title, "content": content}))
PY
)

RESPONSE=$(curl -sS -X POST https://www.moltbook.com/api/v1/posts \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# Check for suspension
if echo "$RESPONSE" | grep -q "suspended"; then
  echo "🚫 Account is suspended: $RESPONSE" >&2
  exit 1
fi

# Check response
if echo "$RESPONSE" | grep -q '"id"'; then
  # --- Check for verification challenge ---
  if echo "$RESPONSE" | grep -q '"verification_required"\s*:\s*true\|"verification_status"\s*:\s*"pending"\|"verification_code"'; then
    echo "🔐 Verification challenge detected — solving..." >&2
    SOLVED=$(solve_challenge "$RESPONSE" 2>&2) || {
      echo "✗ Failed to solve verification challenge" >&2
      exit 1
    }

    V_CODE=$(echo "$SOLVED" | python3 -c "import json,sys; print(json.load(sys.stdin)['verification_code'])")
    V_ANSWER=$(echo "$SOLVED" | python3 -c "import json,sys; print(json.load(sys.stdin)['answer'])")

    if submit_verification "$V_CODE" "$V_ANSWER"; then
      echo "✓ Posted and verified on Moltbook: $TITLE"
      exit 0
    else
      echo "✗ Post created but verification failed" >&2
      exit 1
    fi
  fi

  # No verification needed
  echo "✓ Posted to Moltbook: $TITLE"
  exit 0
elif echo "$RESPONSE" | grep -q "Rate limit\|429\|rate limit"; then
  RETRY=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('retry_after_minutes', d.get('retryAfter','unknown')))" 2>/dev/null || echo "unknown")
  echo "⏱️  Rate limited — try again in ${RETRY} minutes" >&2
  exit 2
else
  echo "✗ Failed to post: $RESPONSE" >&2
  exit 1
fi
