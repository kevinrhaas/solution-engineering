#!/usr/bin/env bash
#
# moltbook-engage-tool.sh — Agent engagement tool (read posts + comment)
#
# This script is copied into the OpenClaw agent workspace at:
#   ~/.openclaw/agents/<agent-name>/moltbook-engage-tool.sh
# The agent uses it to read community posts and leave thoughtful comments.
#
# Credentials are loaded from agent-config.json (same directory as script,
# or fallback to ~/.openclaw/agents/pentaho-pdc-analytics/agent-config.json).
#
# Commands:
#   read [submolt] [limit]        — List recent posts (default: technology, 10)
#   comments <post_id>            — Show comments on a specific post
#   comment <post_id> "content"   — Post a comment on a specific post
#
# Engagement workflow (how the agent uses this):
#   1. read technology 5         — Scan recent posts
#   2. comments <post_id>        — Check existing discussion
#   3. comment <post_id> "..."   — Add a thoughtful reply
#
# Exit codes:
#   0 — Success
#   1 — Error
#   2 — Rate limited
#

set -euo pipefail

cleanup() {
  rm -f post_content.txt moltbook_post.txt moltbook_post_content.txt
}
trap cleanup EXIT

# --- Config Loading ---
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

# --- Functions ---

read_posts() {
  local submolt="${1:-technology}"
  local limit="${2:-10}"

  RESPONSE=$(curl -sS "$API_BASE/posts?submolt=$submolt&limit=$limit" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json")

  # Parse and display posts in a readable format
  python3 - "$RESPONSE" <<'PY'
import json, sys, textwrap

data = json.loads(sys.argv[1])
if not data.get("success"):
    print(f"Error: {data.get('message', 'Unknown error')}")
    sys.exit(1)

posts = data.get("posts", [])
if not posts:
    print("No posts found.")
    sys.exit(0)

print(f"Found {len(posts)} posts:\n")
for i, post in enumerate(posts, 1):
    post_id = post["id"]
    title = post.get("title", "(no title)")
    author = post.get("author", {}).get("name", "unknown")
    comments = post.get("comment_count", 0)
    score = post.get("score", 0)
    content = post.get("content", "")
    # Truncate content for preview
    preview = content[:300].replace("\n", " ")
    if len(content) > 300:
        preview += "..."

    submolt_info = post.get("submolt", {})
    submolt_name = submolt_info.get("name", "unknown") if isinstance(submolt_info, dict) else "unknown"

    print(f"--- Post {i} ---")
    print(f"  ID:       {post_id}")
    print(f"  Title:    {title}")
    print(f"  Author:   {author}")
    print(f"  Submolt:  m/{submolt_name}")
    print(f"  Score:    {score} | Comments: {comments}")
    print(f"  Preview:  {preview}")
    print()
PY
}

post_comment() {
  local post_id="$1"
  local content="$2"
  local max_retries=3
  local attempt=0

  # Use python to safely build JSON payload (handles quotes and special chars)
  PAYLOAD=$(python3 -c "import json,sys; print(json.dumps({'content': sys.stdin.read().rstrip(chr(10))}))" <<< "$content")

  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))

    RESPONSE=$(curl -sS -X POST "$API_BASE/posts/$post_id/comments" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD")

    # Check for suspension (403)
    if echo "$RESPONSE" | grep -q "suspended"; then
      echo "🚫 Account is suspended: $RESPONSE" >&2
      exit 1
    fi

    # Check response
    if echo "$RESPONSE" | grep -q '"success":true'; then
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
          COMMENT_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('comment',{}).get('id','unknown'))" 2>/dev/null || echo "unknown")
          echo "✓ Comment posted and verified (ID: $COMMENT_ID) on post $post_id"
          exit 0
        else
          echo "✗ Comment created but verification failed" >&2
          exit 1
        fi
      fi

      # No verification needed (trusted agent or admin)
      COMMENT_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['comment']['id'])" 2>/dev/null || echo "unknown")
      echo "✓ Comment posted (ID: $COMMENT_ID) on post $post_id"
      exit 0
    elif echo "$RESPONSE" | grep -q "cooldown\|429\|Rate limit\|rate limit"; then
      WAIT=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('retry_after_seconds', d.get('retryAfter', 15)))" 2>/dev/null || echo "15")
      echo "⏱️  Cooldown (attempt $attempt/$max_retries) — waiting ${WAIT}s..." >&2
      sleep "$WAIT"
    else
      echo "✗ Failed to comment: $RESPONSE" >&2
      exit 1
    fi
  done

  echo "✗ Comment failed after $max_retries retries (cooldown)" >&2
  exit 2
}

read_comments() {
  local post_id="$1"

  RESPONSE=$(curl -sS "$API_BASE/posts/$post_id/comments?sort=new&limit=200" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json")

  python3 - "$RESPONSE" <<'PY'
import json, sys

data = json.loads(sys.argv[1])
if not data.get("success"):
    print(f"Error: {data.get('message', 'Unknown error')}")
    sys.exit(1)

comments = data.get("comments", [])
if not comments:
    print("No comments on this post.")
    sys.exit(0)

print(f"Found {len(comments)} top-level comment(s):\n")
for i, c in enumerate(comments, 1):
    author = c.get("author", {}).get("name", "unknown")
    content = c.get("content", "")[:400]
    score = c.get("score", 0)
    replies = c.get("reply_count", 0)
    print(f"  [{i}] {author} (score: {score}, replies: {replies})")
    print(f"      {content[:200]}")
    if len(content) > 200:
        print(f"      ...")
    print()
PY
}

follow_author() {
  local author_name="$1"

  RESPONSE=$(curl -sS -X POST "$API_BASE/agents/$author_name/follow" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json")

  if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "✓ Now following $author_name"
  elif echo "$RESPONSE" | grep -q 'already'; then
    echo "↳ Already following $author_name"
  else
    echo "⚠ Could not follow $author_name: $RESPONSE" >&2
  fi
}

# --- Main ---
ACTION="${1:-}"

case "$ACTION" in
  read)
    SUBMOLT="${2:-technology}"
    LIMIT="${3:-10}"
    read_posts "$SUBMOLT" "$LIMIT"
    ;;
  comments)
    POST_ID="${2:-}"
    if [[ -z "$POST_ID" ]]; then
      echo "Usage: $0 comments <post_id>" >&2
      exit 1
    fi
    read_comments "$POST_ID"
    ;;
  comment)
    POST_ID="${2:-}"
    CONTENT="${3:-}"
    if [[ -z "$POST_ID" || -z "$CONTENT" ]]; then
      echo "Usage: $0 comment <post_id> \"<comment content>\"" >&2
      exit 1
    fi
    post_comment "$POST_ID" "$CONTENT"
    ;;
  follow)
    AUTHOR="${2:-}"
    if [[ -z "$AUTHOR" ]]; then
      echo "Usage: $0 follow <author_name>" >&2
      exit 1
    fi
    follow_author "$AUTHOR"
    ;;
  upvote)
    POST_ID="${2:-}"
    if [[ -z "$POST_ID" ]]; then
      echo "Usage: $0 upvote <post_id>" >&2
      exit 1
    fi
    upvote_post "$POST_ID"
    ;;
  *)
    echo "Moltbook Engagement Tool"
    echo ""
    echo "Usage:"
    echo "  $0 read [submolt] [limit]       — Read recent posts (default: technology, 10)"
    echo "  $0 comments <post_id>           — Read comments on a post"
    echo "  $0 comment <post_id> \"content\"  — Post a comment on a post"
    echo "  $0 follow <author_name>         — Follow an author"
    echo "  $0 upvote <post_id>             — Upvote a post"
    echo ""
    echo "Available submolts for your topics:"
    echo "  technology, ai, agents, engineering, builds, todayilearned,"
    echo "  openclaw-explorers, tooling, coding, general"
    exit 1
    ;;
esac
upvote_post() {
  local post_id="$1"
  RESPONSE=$(curl -sS -X POST "$API_BASE/posts/$post_id/upvote" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json")
  if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "✓ Upvoted post $post_id"
  else
    echo "✗ Failed to upvote: $RESPONSE" >&2
    exit 1
  fi
}
