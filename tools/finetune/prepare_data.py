#!/usr/bin/env python3
"""Turns validated distillation output into train/valid/test splits.

Splits by *problem*, not by example. Four surfaces are generated per problem, so
a random split over examples would put the steps for a problem in train and the
lesson for the same problem in test, and the held-out score would be measuring
memorisation.

Usage: prepare_data.py validated.jsonl [--valid-frac 0.1] [--test-frac 0.1]
"""
import argparse
import collections
import hashlib
import json
import pathlib
import random
import sys


def problem_key(example: dict) -> str:
    """Group by the problem, which is embedded in the prompt."""
    prompt = example["messages"][0]["content"]
    return hashlib.sha256(prompt.encode()).hexdigest()[:16]


def surface_of(example: dict) -> str:
    prompt = example["messages"][0]["content"]
    for name, marker in [("steps", "Solve it step by step"),
                         ("lesson", "Teach the underlying math concept"),
                         ("formulas", "key mathematical formulas"),
                         ("videos", "YouTube educational videos")]:
        if marker in prompt:
            return name
    return "unknown"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--valid-frac", type=float, default=0.1)
    parser.add_argument("--test-frac", type=float, default=0.1)
    parser.add_argument("--seed", type=int, default=20260822)
    parser.add_argument("--out", default="tools/finetune/data")
    args = parser.parse_args()

    examples = [json.loads(l) for l in open(args.input) if l.strip()]
    if not examples:
        sys.exit("no examples")

    # Deduplicate on the whole example: repeated identical targets add nothing
    # and skew the loss.
    seen, unique = set(), []
    for e in examples:
        digest = hashlib.sha256(json.dumps(e, sort_keys=True).encode()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        unique.append(e)

    by_problem = collections.defaultdict(list)
    for e in unique:
        by_problem[problem_key(e)].append(e)

    keys = sorted(by_problem)
    random.Random(args.seed).shuffle(keys)
    n_valid = max(1, int(len(keys) * args.valid_frac))
    n_test = max(1, int(len(keys) * args.test_frac))
    splits = {
        "valid": keys[:n_valid],
        "test": keys[n_valid:n_valid + n_test],
        "train": keys[n_valid + n_test:],
    }

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, group in splits.items():
        rows = [e for k in group for e in by_problem[k]]
        (out / f"{name}.jsonl").write_text(
            "\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
        surfaces = collections.Counter(surface_of(r) for r in rows)
        print(f"{name:6s} {len(group):4d} problems  {len(rows):5d} examples  "
              f"{dict(surfaces)}")

    dropped = len(examples) - len(unique)
    print(f"\ndeduplicated: {dropped} exact duplicates removed")
    print(f"problems held out entirely: {n_valid + n_test} of {len(keys)}")


if __name__ == "__main__":
    main()
