#!/usr/bin/env python3
"""Generates the problem list the distillation runs over.

Templated rather than model-generated, for four reasons: it is free, it is
reproducible from a seed, it gives deliberate control over topic coverage, and it
is *provably* synthetic. There is no path by which a student's problem could end
up in here.

The parameters are drawn from ranges chosen to keep answers exact -- integer or
simple rational -- because a target the grader cannot check is a target we cannot
trust.

Usage: make_problems.py [--count N] [--seed N] > problems.json
"""
import argparse
import json
import random
import sys
from fractions import Fraction

# Problems reserved for evaluation. Training on these would make the headline
# number meaningless, so the templates that could reproduce them are filtered
# against this list by exact text match after rendering.
import pathlib

EVAL_SET = pathlib.Path(__file__).resolve().parents[2] / \
    "Packages/SolvrCore/Sources/solvr-eval/problems.json"


def eval_problem_texts() -> set[str]:
    if not EVAL_SET.exists():
        print(f"warning: eval set not found at {EVAL_SET}", file=sys.stderr)
        return set()
    data = json.loads(EVAL_SET.read_text())
    return {p["problem"].strip().lower() for p in data["problems"]}


def templates(rng: random.Random):
    """Each entry yields (topic, problem text). Answers are not stored: the
    hosted model produces the worked solution, and the graders check it."""
    a = lambda lo=2, hi=9: rng.randint(lo, hi)
    n = lambda lo=2, hi=5: rng.randint(lo, hi)

    yield "algebra", f"Solve for x: {a()}x + {a()} = {a(10, 40)}"
    yield "algebra", f"Solve for x: {a()}x - {a()} = {a(1, 20)}"
    r1, r2 = a(1, 9), a(1, 9)
    yield "algebra", f"Factor completely: x^2 + {r1 + r2}x + {r1 * r2}"
    yield "algebra", f"Expand and simplify: (x + {a()})(x - {a()})"
    yield "algebra", f"Solve for x: x^2 = {a(2, 12) ** 2}"
    yield "algebra", f"Simplify: (x^{n()} \\cdot x^{n()}) / x^{n()}"
    yield "algebra", f"Solve the system: x + y = {a(5, 20)} and x - y = {a(1, 6)}"
    yield "algebra", f"Solve for x: {a()}^x = {a()**n(2, 3)}"

    yield "derivatives", f"Differentiate f(x) = {a()}x^{n()}"
    yield "derivatives", f"Differentiate f(x) = x^{n()} + {a()}x"
    yield "derivatives", f"Differentiate f(x) = {a()}\\sin(x)"
    yield "derivatives", f"Differentiate f(x) = x^{n()} e^x"
    yield "derivatives", f"Differentiate f(x) = \\ln({a()}x)"
    yield "derivatives", f"Differentiate f(x) = ({a()}x + {a()})^{n()}"
    yield "derivatives", f"Find the derivative of f(x) = x^{n()} at x = {a(1, 4)}"
    yield "derivatives", f"Differentiate f(x) = \\frac{{x^{n()}}}{{x + {a()}}}"

    yield "integrals", f"Evaluate the definite integral of {a()}x^{n()} from 0 to {a(1, 3)}"
    yield "integrals", f"Find the indefinite integral of {a()}x^{n()} dx"
    yield "integrals", f"Evaluate the definite integral of {a()}x from {a(1, 3)} to {a(4, 8)}"
    yield "integrals", f"Find the indefinite integral of \\sin({a()}x) dx"
    yield "integrals", f"Find the indefinite integral of e^{{{a()}x}} dx"
    yield "integrals", f"Evaluate the definite integral of 1/x from 1 to e^{n(2, 3)}"
    yield "integrals", f"Find the indefinite integral of x\\cos(x) dx"

    yield "trigonometry", f"Evaluate \\sin({rng.choice(['pi/6','pi/4','pi/3','pi/2'])})"
    yield "trigonometry", f"Evaluate \\cos({rng.choice(['pi/6','pi/4','pi/3','pi'])})"
    yield "trigonometry", f"Solve \\cos(x) = 0 for x in [0, 2pi]"
    yield "trigonometry", f"Simplify: {a()}\\sin^2(x) + {a()}\\cos^2(x)"
    yield "trigonometry", f"Expand \\cos(2x) using a double angle identity"
    yield "trigonometry", f"Find the period of f(x) = \\sin({a()}x)"

    yield "linear algebra", f"Compute the determinant of [[{a()}, {a()}], [{a()}, {a()}]]"
    yield "linear algebra", f"Compute the dot product of ({a()}, {a()}, {a()}) and ({a()}, {a()}, {a()})"
    yield "linear algebra", f"Find the inverse of [[{a()}, 0], [0, {a()}]]"
    yield "linear algebra", f"Find the eigenvalues of [[{a()}, 0], [0, {a()}]]"
    yield "linear algebra", f"Compute the magnitude of the vector ({a(3,4)}, {a(3,4)})"

    yield "limits and series", f"Evaluate the limit of ({a()}x^2 + {a()})/(x^2 - {a()}) as x approaches infinity"
    yield "limits and series", f"Evaluate the sum of ({Fraction(1, a(2, 5))})^n for n from 0 to infinity"
    yield "limits and series", f"Evaluate the sum of n for n from 1 to {a(5, 30)}"
    yield "limits and series", f"Give the first three terms of the Taylor series of \\sin(x) about x = 0"
    yield "limits and series", f"Evaluate the limit of (x^2 - {a()**2})/(x - {a()}) as x approaches {a()}"

    yield "probability", f"A fair coin is flipped {n(2, 4)} times. What is the probability of all heads?"
    yield "probability", f"How many ways are there to choose {n(2, 3)} items from {a(4, 8)} distinct items?"
    yield "probability", f"What is the expected value of one roll of a fair {rng.choice([4, 6, 8, 12])}-sided die?"
    yield "probability", f"A bag has {a(2, 6)} red and {a(2, 6)} blue balls. What is the probability of drawing red?"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=400)
    parser.add_argument("--seed", type=int, default=20260822)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    reserved = eval_problem_texts()
    seen: set[str] = set()
    collisions: set[str] = set()

    # Keyed by template, not by topic. Balancing by topic alone produced 56 of 60
    # algebra problems from the same template -- technically on-topic and useless
    # for teaching anything. `templates()` yields in a fixed order, so the index
    # identifies the template.
    by_template: dict[int, list[tuple[str, str]]] = {}
    for _ in range(args.count * 30):
        for index, (topic, text) in enumerate(templates(rng)):
            key = text.strip().lower()
            if key in reserved:
                collisions.add(key)
                continue
            if key in seen:
                continue
            seen.add(key)
            by_template.setdefault(index, []).append((topic, text))

    problems = []
    order = sorted(by_template)
    while len(problems) < args.count and any(by_template[i] for i in order):
        progressed = False
        for index in order:
            if not by_template[index] or len(problems) >= args.count:
                continue
            topic, text = by_template[index].pop()
            problems.append({"id": f"gen-{len(problems):04d}", "topic": topic,
                             "template": index, "problem": text})
            progressed = True
        if not progressed:
            break

    json.dump({
        "note": "Templated synthetic problems for distillation. No student work, "
                "no names, no tutoring records. Reproducible from the seed below.",
        "seed": args.seed,
        "excludedBecauseReservedForEvaluation": sorted(collisions),
        "problems": problems,
    }, sys.stdout, indent=1)
    print(file=sys.stdout)
    print(f"{len(problems)} problems from {len(order)} templates, {len(collisions)} distinct problems skipped as reserved for evaluation",
          file=sys.stderr)


if __name__ == "__main__":
    main()
