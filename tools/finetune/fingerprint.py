#!/usr/bin/env python3
"""A fingerprint of the weights a server is actually serving.

Several prompts, not one. A single short completion at temperature 0 is a weak
discriminator -- two genuinely different models agreed on one exactly, which read
as "the adapter did not load" when the adapter had loaded fine. Concatenating a
few answers of different shapes makes a collision vanishingly unlikely.

The point of it is to fail loudly before spending fifteen minutes measuring the
wrong weights, which is exactly what happened when three evaluation arms silently
served one model and produced byte-identical results that looked plausible.

Usage: fingerprint.py <base-url> <model>
"""
import hashlib
import json
import sys
import urllib.request

PROMPTS = [
    "Differentiate f(x) = x^7 + 2x. Answer in one line.",
    ("The student submitted this problem: 'Differentiate f(x) = 4x^5 + 3x'. "
     "Solve it step by step.\n\nReturn ONLY a valid JSON array with this structure:\n"
     '[{"step": 1, "title": "T", "explanation": "E", "math": "\\\\frac{x}{y}"}]\n'
     "Return ONLY the JSON array, no fences."),
    ("The student submitted this problem: 'Evaluate the definite integral of "
     "5x^2 from 0 to 2'. List 3-6 key mathematical formulas relevant to it.\n"
     'Return ONLY a JSON array: [{"name":"N","formula":"F","description":"D"}]'),
]

url, model = sys.argv[1], sys.argv[2]
chunks = []
for prompt in PROMPTS:
    body = json.dumps({"model": model, "max_tokens": 500, "temperature": 0,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request(f"{url}/v1/chat/completions", body,
                                 {"content-type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=600))
    chunks.append(d["choices"][0]["message"].get("content") or "")
print(hashlib.sha256("\x00".join(chunks).encode()).hexdigest()[:16])
