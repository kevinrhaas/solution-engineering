#!/usr/bin/env python3
"""Test the improved LLM solver with pre-cleaning against failed challenges."""
import re, json, urllib.request, os

# Load OpenAI key
config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path) as f:
    OPENAI_KEY = json.load(f)["skills"]["entries"]["openai-whisper-api"]["apiKey"]

def clean_challenge(text):
    cleaned = re.sub(r'[^a-zA-Z0-9\s]', '', text)
    cleaned = re.sub(r'(.)\1{2,}', r'\1', cleaned)
    cleaned = re.sub(r'([a-zA-Z])\1', r'\1', cleaned)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned

def solve_with_llm(challenge_text, api_key):
    cleaned = clean_challenge(challenge_text)
    prompt = (
        "You are solving a math word problem that has been obfuscated. I have partially cleaned it for you.\n\n"
        f"Original (obfuscated): \"{challenge_text}\"\n"
        f"Cleaned: \"{cleaned}\"\n\n"
        "Remaining obfuscation patterns to watch for:\n"
        "- Words may still be split across spaces: 'tw en ty th re e' = 'twenty three' = 23\n"
        "- Extra letters may be prepended/appended: 'sthirty' = 'thirty', 'um' is filler\n"
        "- Characters may be doubled: 'fiffteen' = 'fifteen' = 15\n\n"
        "IMPORTANT: Identify the OPERATION from context words:\n"
        "- 'adds', 'plus', 'total', 'combined', 'and...more' → +\n"
        "- 'slows', 'loses', 'minus', 'reduced', 'less' → -\n"
        "- 'times', 'multiplied' → *\n"
        "- 'divided', 'split among' → /\n\n"
        "Extract EXACTLY two numbers and one operation. Compute the answer.\n\n"
        "Reply with ONLY a JSON object:\n"
        '{"num1": <number>, "num2": <number>, "operation": "+"|"-"|"*"|"/", "answer": <number>}\n'
    )
    body = json.dumps({
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": 150,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        result = json.loads(resp.read())
    content = result["choices"][0]["message"]["content"].strip()
    content = re.sub(r'^```json\s*', '', content)
    content = re.sub(r'\s*```$', '', content)
    parsed = json.loads(content)
    return parsed

# Test cases: (challenge, expected_answer)
tests = [
    # Failed test 1: "twenty three" split as "TrW eNnY ThReE", slows by 7 → 23-7=16
    (
        "A] Lo^bS tEr SwImS/ aT TrW eNnY ThReE MeTeRs PeR SeCoNd, Um~ DuRiNg DoMiNaNcE FiGhT It SlOwS\\ bY SeVeN MeTeRs, WhAtS NeW SpEeD?",
        16.0
    ),
    # Failed test 2: fifteen + three = 18 (total force)
    (
        "A] lO.oBbSsTtErRr'Ss ClLaWw^ aPpPlIiEeSs- fIfFtEeEn ] nEeWwToOnNs, Um- aNd] tHe/ anTeNnAa TaPpEeRr A/ddSs- tHrReEe } nEeWwToOnNs, WhHaTt| iIs^ tHe/ ToTaL- FoOrCe? ~ lo.b st errr lxobqstwer phyysxics velooocityyy umm",
        18.0
    ),
    # Original hard case from earlier today
    (
        "a looobbsstter }claaw exert sthirty two~ newwtons |and the waterp ressure um adds <four teen> newwtons",
        46.0
    ),
    # Standard case: accelerates by seven
    (
        "A] lO^bS tEr S[wImS aT/ tW]eNnY fIfE- ceNtI mE]tErS pEr- SeC^oNd ]anD^ acCeL-eRAtEs bY/ sEvEn~, wHaT]s ThE nEw- veLoOcI tY?",
        32.0
    ),
]

print("Testing improved solver (gpt-4o + pre-cleaning):\n")
all_pass = True
for i, (challenge, expected) in enumerate(tests, 1):
    cleaned = clean_challenge(challenge)
    print(f"Test {i}:")
    print(f"  RAW:      {challenge[:90]}...")
    print(f"  CLEANED:  {cleaned[:90]}...")
    result = solve_with_llm(challenge, OPENAI_KEY)
    answer = float(result["answer"])
    status = "✅ PASS" if answer == expected else "❌ FAIL"
    if answer != expected:
        all_pass = False
    print(f"  RESULT:   {result['num1']} {result['operation']} {result['num2']} = {answer}")
    print(f"  EXPECTED: {expected}")
    print(f"  {status}")
    print()

print(f"{'='*40}")
print(f"{'ALL TESTS PASSED ✅' if all_pass else 'SOME TESTS FAILED ❌'}")
