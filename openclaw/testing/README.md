# Testing Directory

This directory contains test scripts for validating and improving the Moltbook verification challenge solver.

## Files

| File | Purpose |
|---|---|
| `test_solver.py` | Basic solver test with word-based number extraction |
| `test_improved_solver.py` | Improved deobfuscation algorithm tests |
| `test_llm_solver.py` | LLM-based challenge solver tests using GPT-4o-mini |

## Challenge Solver Overview

Moltbook sends obfuscated math word problems as verification challenges. These challenges include:
- Random symbols (`}`, `|`, `<`, `>`, `~`, etc.)
- Repeated characters (`looobbsstter`, `fIfFtEeEn`)
- Split words across spaces (`four teen`, `tw en ty`)
- Extra letters (`sthirty`, `um`)
- Alternating case (`TrW eNnY ThReE`)

## Test Scripts

### test_solver.py

Early experimental solver using regex-based deobfuscation:
- Strips non-alphanumeric characters
- Collapses repeated characters
- Attempts substring matching for number words
- Uses sliding window approach

This was the initial approach before moving to LLM-based solving.

### test_improved_solver.py

Improved deobfuscation with:
- More sophisticated character deduplication
- Two-word join detection (`four teen` → `fourteen`)
- Partial vs. full deduplication strategies
- Vowel preservation during dedup

This helped refine the pre-cleaning logic before sending to the LLM.

### test_llm_solver.py

**Production solver approach** — the actual implementation used in production tools:
- Uses OpenAI GPT-4o-mini for solving
- Pre-cleans challenge text with regex
- Extracts operation type from context words
- Returns structured JSON with answer
- Includes real test cases from Moltbook

This script validates the solver logic that's embedded in:
- `agents/*/moltbook-post-tool.sh`
- `agents/*/moltbook-engage-tool.sh`
- `tools/moltbook-post-tool.sh`
- `tools/moltbook-engage-tool.sh`

## Running Tests

Each script is standalone and can be run directly:

```bash
# Test basic solver
python3 test_solver.py

# Test improved solver  
python3 test_improved_solver.py

# Test LLM solver (requires OpenAI API key in ~/.openclaw/openclaw.json)
python3 test_llm_solver.py
```

## Production Implementation

The production challenge solver is embedded as a Python function within the bash tool scripts. It uses the approach validated by `test_llm_solver.py`:

```python
def solve_with_llm(challenge_text, api_key):
    # Pre-clean the challenge
    cleaned = re.sub(r'[^a-zA-Z0-9\s]', '', challenge_text)
    cleaned = re.sub(r'(.)\1{2,}', r'\1', cleaned)
    # ... more cleaning
    
    # Send to OpenAI with structured prompt
    # Returns: {"num1": N, "num2": M, "operation": "+", "answer": X}
```

This function is called automatically when the tools receive a verification challenge from Moltbook's API.

---

**Last updated:** February 26, 2026
