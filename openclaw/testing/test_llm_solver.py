#!/usr/bin/env python3
"""Test the LLM-based challenge solver against known obfuscated challenges."""

import json
import os
import re
import urllib.request

# OpenAI key from openclaw config
OPENCLAW_CONFIG = os.path.expanduser("~/.openclaw/openclaw.json")
with open(OPENCLAW_CONFIG) as f:
    cfg = json.load(f)
OPENAI_KEY = cfg["skills"]["entries"]["openai-whisper-api"]["apiKey"]


def solve_challenge_llm(challenge_text: str) -> dict:
    """Use OpenAI to solve an obfuscated math challenge.
    
    Returns dict with 'answer' (str, 2 decimal places) and 'explanation' (str).
    """
    prompt = (
        "You are solving an obfuscated math word problem from a verification system. "
        "The text has random symbols, extra letters, repeated characters, and misspellings injected. "
        "Extract the two numbers and the math operation, then compute the answer.\n\n"
        f"Challenge text: \"{challenge_text}\"\n\n"
        "Reply with ONLY a JSON object, no markdown, no explanation outside the JSON:\n"
        '{"num1": <number>, "num2": <number>, "operation": "+"|"-"|"*"|"/", "answer": <number>}\n'
    )

    body = json.dumps({
        "model": "gpt-4o-mini",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": 150,
    }).encode()

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {OPENAI_KEY}",
            "Content-Type": "application/json",
        },
    )

    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())

    content = result["choices"][0]["message"]["content"].strip()
    # Strip markdown code fences if present
    content = re.sub(r'^```json\s*', '', content)
    content = re.sub(r'\s*```$', '', content)
    parsed = json.loads(content)

    answer = float(parsed["answer"])
    return {
        "answer": f"{answer:.2f}",
        "explanation": f"{parsed.get('num1')} {parsed.get('operation')} {parsed.get('num2')} = {answer}",
    }


# Test cases — real obfuscated challenges from Moltbook
test_cases = [
    # The one that failed today
    (
        "a looobbsstter }claaw exert sthirty two~ newwtons |and the waterp ressure um adds <four teen> newwtons, whats+ the total force??",
        "46.00",
    ),
    # Classic bracket/symbol obfuscation
    (
        "A] lO^bSt-Er S[wImS aT/ tW]eNn-Tyy mE^tE[rS aNd] SlO/wS bY^ fI[vE",
        "15.00",
    ),
    # Simple digit version
    (
        "a lobster has 42 shells and loses 17, how many remain?",
        "25.00",
    ),
    # Multiplication
    (
        "thee loobster ccatches fivve fish timmes eighht dailyyy",
        "40.00",
    ),
    # Division
    (
        "a looobster divides sixtyyy clams among fourr friends",
        "15.00",
    ),
]

print("🧪 Testing LLM-based challenge solver\n")
all_pass = True
for i, (challenge, expected) in enumerate(test_cases, 1):
    try:
        result = solve_challenge_llm(challenge)
        got = result["answer"]
        status = "✅" if got == expected else "❌"
        if got != expected:
            all_pass = False
        print(f"  {status} Test {i}: expected={expected}, got={got}")
        print(f"     Explanation: {result['explanation']}")
        print(f"     Challenge: {challenge[:80]}...")
    except Exception as e:
        print(f"  ❌ Test {i}: ERROR: {e}")
        all_pass = False
    print()

print("=" * 60)
print(f"{'✅ ALL TESTS PASSED' if all_pass else '❌ SOME TESTS FAILED'}")
