#!/usr/bin/env python3
"""Read and summarize an OpenClaw session log."""
import sys, json

path = sys.argv[1] if len(sys.argv) > 1 else ""
if not path:
    print("Usage: python3 read_session.py <session.jsonl>")
    sys.exit(1)

with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except:
            continue
        role = obj.get("role", "")
        if role == "assistant":
            content = obj.get("content", "")
            if content:
                print(f"[ASSISTANT] {content[:600]}")
            tool_calls = obj.get("tool_calls", [])
            for tc in tool_calls:
                fn = tc.get("function", {})
                print(f"[TOOL_CALL] {fn.get('name')}: {str(fn.get('arguments', ''))[:400]}")
        elif role == "tool":
            content = obj.get("content", "")
            print(f"[TOOL_RESULT] {content[:600]}")
