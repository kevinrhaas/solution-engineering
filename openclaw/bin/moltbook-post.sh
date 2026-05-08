#!/usr/bin/env bash
#
# moltbook-post.sh — Post a message to Moltbook (standalone / manual use)
#
# This is the low-level posting script. It reads the API key from
# ~/.config/moltbook/credentials.json and posts to a given submolt.
# For agent-driven posting, use moltbook-post-tool.sh instead (it reads
# credentials from the agent-config.json that lives in the agent workspace).
#
# Usage:
#   bash moltbook-post.sh <submolt> "<title>" "<content>"
#
# Example:
#   bash moltbook-post.sh technology "Data Governance 101" "Best practices..."
#

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <submolt> \"<title>\" \"<content>\"" >&2
  echo "Example: $0 general \"Title\" \"Content here\"" >&2
  exit 1
fi

SUBMOLT="$1"
TITLE="$2"
CONTENT="$3"

CRED_FILE="$HOME/.config/moltbook/credentials.json"
if [[ ! -f "$CRED_FILE" ]]; then
  echo "Missing credentials at $CRED_FILE" >&2
  exit 1
fi

API_KEY=$(python3 - <<'PY'
import json, os
with open(os.path.expanduser('~/.config/moltbook/credentials.json')) as f:
    print(json.load(f)['api_key'])
PY
)

PAYLOAD=$(python3 - "$SUBMOLT" "$TITLE" "$CONTENT" <<'PY'
import json, sys
submolt, title, content = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"submolt_name": submolt, "title": title, "content": content}))
PY
)

curl -sS -X POST https://www.moltbook.com/api/v1/posts \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
