#!/usr/bin/env python3
"""Test improved challenge solver deobfuscation."""
import re

challenges = [
    "a looobbsstter }claaw exert sthirty two~ newwtons |and the waterp ressure um adds <four teen> newwtons, whats+ the total force??",
    "If a penguin weighs twenty-five kilograms and eats three fish, how heavy is it?",
    "The rooocket travels at 150 km/h and slooows by 30 km/h. What speed??",
    "An agent processes forty two requests and gains eighteen more. Total?",
]

def solve(challenge):
    print(f"\n{'='*60}")
    print(f"INPUT: {challenge}")

    # Step 1: Strip ALL non-alpha, non-digit, non-space chars
    clean = re.sub(r'[^a-zA-Z0-9\s]', '', challenge)
    # Step 2: Normalize whitespace
    clean = re.sub(r'\s+', ' ', clean).strip().lower()
    print(f"After strip: '{clean}'")

    # Step 3: Collapse runs of 3+ identical chars to 2 (preserves 'ee' in 'teen', 'ee' in 'three')
    deduped = re.sub(r'(.)\1{2,}', r'\1\1', clean)
    # Step 4: Then collapse 2+ to 1 ONLY for consonants (preserve vowel doubles like ee, oo)
    # Actually, better: do full dedup but also try pre-dedup matching
    full_dedup = re.sub(r'(.)\1+', r'\1', clean)
    print(f"After partial dedup: '{deduped}'")
    print(f"After full dedup: '{full_dedup}'")

# Number word list (base words only for substring matching)
BASE_NUMBERS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
    "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100,
    "thousand": 1000, "million": 1000000,
}

# Approach: scan deduped text, try to find number words as substrings of each word
words = deduped.split()
print(f"\nWords: {words}\n")

for w in words:
    # Check exact match
    if w in BASE_NUMBERS:
        print(f"  EXACT: '{w}' = {BASE_NUMBERS[w]}")
        continue
    # Check if a known number word is a substring
    found = []
    for nw in sorted(BASE_NUMBERS.keys(), key=len, reverse=True):
        if nw in w and len(nw) >= 3:  # avoid tiny false positives
            found.append(nw)
    if found:
        print(f"  SUBSTR: '{w}' contains {found}")
    # Check numeric
    try:
        val = float(w)
        print(f"  DIGIT: '{w}' = {val}")
    except ValueError:
        pass

# New strategy: join all words, then scan for known number words as substrings
print("\n--- Sliding window approach on full deduped text ---")
full = deduped.replace(' ', '')
print(f"Full joined: '{full}'")
found_numbers = []
for nw in sorted(BASE_NUMBERS.keys(), key=len, reverse=True):
    for m in re.finditer(re.escape(nw), full):
        found_numbers.append((m.start(), nw, BASE_NUMBERS[nw]))
found_numbers.sort()
print(f"Found: {found_numbers}")

# But we need to also try the two-word join approach for "four teen" -> "fourteen"
print("\n--- Two-word join scan ---")
for i in range(len(words) - 1):
    joined = words[i] + words[i+1]
    if joined in BASE_NUMBERS:
        print(f"  JOIN: '{words[i]}' + '{words[i+1]}' = '{joined}' = {BASE_NUMBERS[joined]}")
    # also try after dedup of joined
    joined_dedup = re.sub(r'(.)\1+', r'\1', joined)
    if joined_dedup in BASE_NUMBERS and joined_dedup != joined:
        print(f"  JOIN+DEDUP: '{words[i]}' + '{words[i+1]}' -> '{joined_dedup}' = {BASE_NUMBERS[joined_dedup]}")
