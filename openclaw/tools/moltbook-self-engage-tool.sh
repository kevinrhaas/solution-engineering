#!/usr/bin/env bash
# moltbook-self-engage-tool.sh — Engage with comments on your own posts
# Usage:
#   bash moltbook-self-engage-tool.sh read_posts [limit]
#   bash moltbook-self-engage-tool.sh read_comments <POST_ID>
#   bash moltbook-self-engage-tool.sh reply <POST_ID> "REPLY_CONTENT"
#
# Reads posts authored by pentaho-pdc-analytics, lists comments, and allows replying to comments.

set -euo pipefail

cleanup() {
  rm -f post_content.txt moltbook_post.txt moltbook_post_content.txt
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

AGENT_NAME="pentaho-pdc-analytics"
API_BASE="https://www.moltbook.com/api/v1"
API_KEY=$(python3 -c "import json; print(json.load(open('$AGENT_CONFIG'))['api_key'])")

follow_author() {
  local author_name="$1"
  RESPONSE=$(curl -sS -X POST "$API_BASE/agents/$author_name/follow" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json")
  if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "✓ Now following $author_name"
  elif echo "$RESPONSE" | grep -q 'already'; then
    echo "☳ Already following $author_name"
  else
    echo "⚡ Could not follow $author_name: $RESPONSE" >&2
  fi
}

case "${1:-}" in
  read_posts)
    LIMIT="${2:-10}"
    RAW=$(curl -s "$API_BASE/posts?author=$AGENT_NAME&sort=new&limit=$LIMIT" -H "x-api-key: $API_KEY")
    printf '%s' "$RAW" | python3 -c 'import sys, json; data=json.load(sys.stdin); posts=data.get("posts", []); print("No posts found.") if not posts else [print("{} | {} | {}".format(p["id"], p["title"], p["created_at"])) for p in posts]'
    ;;
  read_comments)
    POST_ID="${2:?POST_ID required}"
    curl -s "$API_BASE/posts/$POST_ID/comments?sort=new&limit=200" \
      -H "x-api-key: $API_KEY" | \
      python3 -c 'import sys, json; data=json.load(sys.stdin); [print("{} | {} | {}\n{}\n---".format(c["id"], c["author"]["name"], c["created_at"], c["content"])) for c in data.get("comments", [])]'
    ;;
  reply)
    POST_ID="${2:?POST_ID required}"
    REPLY_CONTENT="${3:?Reply content required}"
    echo "[DEBUG] Reply content: $REPLY_CONTENT" >&2
    # Escape reply content for JSON (single-line, robust)
    ESCAPED_REPLY_CONTENT=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$REPLY_CONTENT")
    echo "[DEBUG] Escaped reply content: $ESCAPED_REPLY_CONTENT" >&2
    
    # Get the author of the first non-self comment on the post
    AUTHOR_NAME=$(curl -s "$API_BASE/posts/$POST_ID/comments?sort=new&limit=200" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" | \
      python3 -c "import sys, json; data=json.load(sys.stdin); print(next((c['author']['name'] for c in data.get('comments', []) if c['author']['name'] != '$AGENT_NAME'), ''))")
    
    curl -s -X POST "$API_BASE/posts/$POST_ID/comments" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"content\": \"$ESCAPED_REPLY_CONTENT\"}"
      
    if [[ -n "$AUTHOR_NAME" ]]; then
      follow_author "$AUTHOR_NAME"
    fi
    ;;
  *)
    echo "Usage: $0 read_posts [limit]"
    echo "       $0 read_comments <POST_ID>"
    echo "       $0 reply <POST_ID> \"REPLY_CONTENT\""
    exit 1
    ;;
esac