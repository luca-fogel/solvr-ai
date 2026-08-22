#!/usr/bin/env python3
"""Grades the final answer of a worked solution.

Two things this deliberately does not do.

It does not compare strings. "2/4", "0.5" and "\\frac{1}{2}" are one answer, and
a grader that calls two of those wrong is measuring formatting, not mathematics.
So the answer is parsed into a symbolic expression and compared for
equivalence -- numerically when the expected answer is a single real number,
symbolically otherwise.

It does not use a language model as a judge. A model grading output from its own
family agrees with itself for reasons that have nothing to do with correctness.
Where symbolic comparison cannot decide, the verdict is `null` -- unknown, to be
hand-checked -- rather than a guess.

Usage: grade_answers.py in.jsonl > out.jsonl
"""
import json
import re
import sys
import warnings

warnings.filterwarnings("ignore")

import sympy
from sympy.parsing.latex import parse_latex


def clean(tex: str) -> str:
    """Strip the presentation and keep the mathematics."""
    s = tex.strip()
    s = re.sub(r"^\$+|\$+$", "", s)
    s = re.sub(r"^\\\(|\\\)$", "", s)
    s = re.sub(r"\\(left|right)\b", "", s)
    s = re.sub(r"\\[,;!qquad]+", " ", s)
    s = re.sub(r"\\text\{[^}]*\}", "", s)
    s = re.sub(r"\\boxed\{(.*)\}", r"\1", s)
    # A final line is often written as "= 1" or "x = 1"; the answer is the tail.
    if "=" in s:
        s = s.split("=")[-1]
    return s.strip().rstrip(".")


def to_expr(tex: str):
    s = clean(tex)
    if not s:
        return None
    for attempt in (s, s.replace("^", "**")):
        try:
            expr = parse_latex(attempt)
        except Exception:
            try:
                expr = sympy.sympify(attempt)
            except Exception:
                continue
        # parse_latex reads a bare `e` as a symbol, not Euler's number.
        e = sympy.Symbol("e")
        if e in getattr(expr, "free_symbols", set()):
            expr = expr.subs(e, sympy.E)
        return expr
    return None


def grade(record):
    """True, False, or None for 'could not decide -- hand-check this one'."""
    answer = record.get("finalAnswer")
    if not answer:
        return None, "no final answer in the response"

    got = to_expr(answer)
    if got is None:
        return None, "could not parse the answer"

    expected_numeric = record.get("expectedNumeric")
    if expected_numeric is not None:
        try:
            value = complex(sympy.N(got))
            if abs(value.imag) > 1e-9:
                return False, f"complex value {value}"
            return abs(value.real - float(expected_numeric)) < 1e-6, f"{value.real} vs {expected_numeric}"
        except Exception:
            return None, "answer is not a number but the expected answer is"

    want = to_expr(record.get("expectedAnswer", ""))
    if want is None:
        return None, "could not parse the expected answer"
    try:
        if sympy.simplify(got - want) == 0:
            return True, "symbolically equal"
        return False, f"{got} != {want}"
    except Exception:
        return None, "symbolic comparison failed"


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: grade_answers.py <results.jsonl>\n")
        raise SystemExit(2)

    counts = {True: 0, False: 0, None: 0}
    with open(sys.argv[1]) as handle:
        for line in handle:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("surface") == "steps" and record.get("ok"):
                verdict, why = grade(record)
                record["answerCorrect"] = verdict
                record["answerNote"] = why
                counts[verdict] += 1
            print(json.dumps(record))

    total = sum(counts.values())
    if total:
        sys.stderr.write(
            f"answers: {counts[True]} correct, {counts[False]} wrong, "
            f"{counts[None]} undecidable (hand-check these) of {total}\n")


if __name__ == "__main__":
    main()
