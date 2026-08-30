#!/usr/bin/env python3
"""Is the maths in the training data right?

Nothing had ever asked. `validate_targets.mjs` checks that every LaTeX string in
a target *renders*, and `make_problems.py` says in its own docstring that
"answers are not stored: the hosted model produces the worked solution, and the
graders check it" -- but the graders were only ever run on the *evaluation*
responses. The 1,103 examples the LoRA was trained on were filtered for
renderability and for nothing else. The only check on their mathematics in the
whole project is a line in the handover: "teacher maths: 5 of 5 step-solutions
hand-checked correct -- manual, sample of 5".

That gap matters more than it looks, because it is a candidate explanation for
the shape of the regression. The fine-tune costs maths correctness at cumulative
225 -- one epoch -- as badly as at 600, which is not what over-training looks
like. Training on wrong arithmetic would do exactly that: immediately, and
without getting much worse.

So this solves the problems itself. They are templated, which is what makes it
possible: `make_problems.py` renders a few dozen shapes with numbers substituted
in, so the answer can be computed from the problem text rather than trusted from
the teacher. Coverage is partial and reported as partial -- a template this does
not know how to solve is skipped, not guessed at.

    tools/finetune/check_targets.py [data/raw.jsonl] [problems.json]

Needs the same interpreter as the graders:
`~/.venvs/solvr-eval/bin/python`, which has sympy.
"""
import json
import pathlib
import re
import sys
import warnings

warnings.filterwarnings("ignore")
import sympy
from sympy import Rational, symbols

# The answer side is read by the *same* code that grades evaluation responses.
# The first version of this script had its own extractor, and it reported 46% of
# the training targets wrong -- because it could not parse `\frac{18}{7}`, so it
# fell back to an earlier step and compared 18 against 18/7. Two extractors is
# how you get two answers; there is one now.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "eval"))
import grade_answers  # noqa: E402

x, y, n = symbols("x y n")


# Each entry: a pattern over the problem text, and a function from its groups to
# the correct answer. Written against `make_problems.py`'s templates.
NUM = r"(-?\d+(?:\.\d+)?)"
SOLVERS = [
    (rf"^Solve for x: {NUM}x \+ {NUM} = {NUM}$",
     lambda a, b, c: Rational(c) - Rational(b) and (Rational(c) - Rational(b)) / Rational(a)),
    (rf"^Solve for x: {NUM}x - {NUM} = {NUM}$",
     lambda a, b, c: (Rational(c) + Rational(b)) / Rational(a)),
    (rf"^Expand and simplify: \(x \+ {NUM}\)\(x - {NUM}\)$",
     lambda a, b: sympy.expand((x + Rational(a)) * (x - Rational(b)))),
    (rf"^Differentiate f\(x\) = {NUM}x\^{NUM}$",
     lambda a, b: sympy.diff(Rational(a) * x ** Rational(b), x)),
    (rf"^Differentiate f\(x\) = x\^{NUM} \+ {NUM}x$",
     lambda a, b: sympy.diff(x ** Rational(a) + Rational(b) * x, x)),
    (rf"^Differentiate f\(x\) = \({NUM}x \+ {NUM}\)\^{NUM}$",
     lambda a, b, c: sympy.diff((Rational(a) * x + Rational(b)) ** Rational(c), x)),
    (rf"^Differentiate f\(x\) = \\frac\{{x\^{NUM}\}}\{{x \+ {NUM}\}}$",
     lambda a, b: sympy.simplify(sympy.diff(x ** Rational(a) / (x + Rational(b)), x))),
    (rf"^Differentiate f\(x\) = {NUM}\\sin\(x\)$",
     lambda a: sympy.diff(Rational(a) * sympy.sin(x), x)),
    (rf"^Differentiate f\(x\) = \\ln\({NUM}x\)$",
     lambda a: sympy.diff(sympy.log(Rational(a) * x), x)),
    (rf"^Find the derivative of f\(x\) = x\^{NUM} at x = {NUM}$",
     lambda a, b: sympy.diff(x ** Rational(a), x).subs(x, Rational(b))),
    (rf"^Evaluate the definite integral of {NUM}x\^{NUM} from {NUM} to {NUM}$",
     lambda a, b, lo, hi: sympy.integrate(
         Rational(a) * x ** Rational(b), (x, Rational(lo), Rational(hi)))),
    (rf"^Evaluate the definite integral of {NUM}x from {NUM} to {NUM}$",
     lambda a, lo, hi: sympy.integrate(Rational(a) * x, (x, Rational(lo), Rational(hi)))),
    (rf"^Find the indefinite integral of {NUM}x\^{NUM} dx$",
     lambda a, b: sympy.integrate(Rational(a) * x ** Rational(b), x), "antiderivative"),
    (rf"^Find the indefinite integral of \\sin\({NUM}x\) dx$",
     lambda a: sympy.integrate(sympy.sin(Rational(a) * x), x), "antiderivative"),
    (rf"^Find the indefinite integral of e\^\{{{NUM}x\}} dx$",
     lambda a: sympy.integrate(sympy.exp(Rational(a) * x), x), "antiderivative"),
    (rf"^Compute the determinant of \[\[{NUM}, {NUM}\], \[{NUM}, {NUM}\]\]$",
     lambda a, b, c, d: sympy.Matrix([[Rational(a), Rational(b)],
                                      [Rational(c), Rational(d)]]).det()),
    (rf"^Compute the dot product of \({NUM}, {NUM}, {NUM}\) and \({NUM}, {NUM}, {NUM}\)$",
     lambda a, b, c, d, e, f: (Rational(a) * Rational(d) + Rational(b) * Rational(e)
                               + Rational(c) * Rational(f))),
    (rf"^Evaluate the sum of n for n from {NUM} to {NUM}$",
     lambda lo, hi: sympy.summation(n, (n, int(lo), int(hi)))),
    (rf"^Evaluate the limit of \(x\^{NUM} - {NUM}\)/\(x - {NUM}\) as x approaches {NUM}$",
     lambda a, b, c, d: sympy.limit(
         (x ** Rational(a) - Rational(b)) / (x - Rational(c)), x, Rational(d))),
    (rf"^A bag has {NUM} red and {NUM} blue balls\. What is the probability of drawing red\?$",
     lambda r, b: Rational(int(r), int(r) + int(b))),
    (rf"^How many ways are there to choose {NUM} items from {NUM} distinct items\?$",
     lambda k, m: sympy.binomial(int(m), int(k))),
    (rf"^Simplify: {NUM}\\sin\^{NUM}\(x\) \+ {NUM}\\cos\^{NUM}\(x\)$",
     lambda a, p, b, q: sympy.simplify(
         Rational(a) * sympy.sin(x) ** Rational(p)
         + Rational(b) * sympy.cos(x) ** Rational(q))),
]


def correct_answer(problem: str):
    """The answer, and how it may legitimately be written."""
    for entry in SOLVERS:
        pattern, solve = entry[0], entry[1]
        kind = entry[2] if len(entry) > 2 else "exact"
        match = re.match(pattern, problem.strip())
        if match:
            try:
                return solve(*match.groups()), kind
            except Exception:
                return None, None
    return None, None


def verdict(candidates, expected, kind):
    """True, False, or None for "could not decide -- do not count this one".

    The three-way answer is the point. The first version of this script had two,
    and every parse failure of its own landed in the `wrong` column: it read
    `C + 4x^5/5` as a disagreement with `4x^5/5`, when a constant of integration
    is what an indefinite integral is *supposed* to have, and `x(x + 8)` as a
    function call rather than a product. A grader that cannot tell its own
    failures from the data's is an instrument that will report whatever number
    you were hoping for.
    """
    for candidate in candidates:
        if grade_answers.same(candidate, expected):
            return True
        # Two antiderivatives agree if they differ by a constant, which is the
        # comparison to make rather than picking one representative and hoping
        # the teacher picked the same one.
        if kind == "antiderivative":
            try:
                if sympy.simplify(sympy.diff(candidate - expected, x)) == 0:
                    return True
            except Exception:
                pass

    # Not provably equal. Is it provably *un*equal? Evaluate the difference at a
    # couple of ordinary points; if it is a definite nonzero number every time,
    # the disagreement is real. Anything else -- an unparsed symbol, a pole, a
    # function application that was meant to be a product -- is undecidable.
    for candidate in candidates:
        try:
            difference = candidate - expected
            probes = []
            for point in (Rational(13, 10), Rational(27, 10), Rational(41, 10)):
                value = complex(difference.subs({x: point, y: point, n: point}).evalf())
                if not (abs(value.real) < 1e12 and abs(value.imag) < 1e12):
                    raise ValueError("not finite here")
                probes.append(value)
            if all(abs(v) > 1e-9 for v in probes):
                return False
        except Exception:
            continue
    return None


def target_answers(target: str):
    """(what the last step says, what any step says).

    Two readings, because they measure different things and conflating them cost
    an earlier version of this script two false accusations.

    `AnthropicPrompts.steps` says "The LAST step should contain the final
    answer", so the last step is what a consumer would take -- and it is
    sometimes wrong to, because the teacher likes to append a verification step:
    `x = 7` at step five, `4(7) + 9 = 28 + 9 = 37` at step six. Reading step six
    as the answer gives 37 for a problem whose answer is 7, and the target was
    never at fault.

    So: whether the working *arrives at* the right answer, and separately whether
    the last step is *where it says it is*.
    """
    try:
        steps = json.loads(target)
    except Exception:
        return [], []
    if not isinstance(steps, list) or not steps:
        return [], []

    def read(step):
        text = step.get("math") or step.get("explanation") or ""
        return grade_answers.expressions(text) if text else []

    last = read(steps[-1])
    every = [e for step in steps for e in read(step)]
    return last, every


def main():
    raw = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "tools/finetune/data/raw.jsonl")
    total = solvable = right = wrong = undecided = last_step_right = 0
    misses = []
    for line in raw.read_text().splitlines():
        if not line.strip():
            continue
        messages = json.loads(line)["messages"]
        prompt, target = messages[0]["content"], messages[-1]["content"]
        if "Solve it step by step" not in prompt:
            continue
        total += 1
        found = re.search(r"submitted this problem: '(.+?)'\.", prompt, re.S)
        if not found:
            continue
        expected, kind = correct_answer(found.group(1))
        if expected is None:
            continue
        solvable += 1
        last, every = target_answers(target)
        if not every:
            undecided += 1
            continue
        if verdict(last, expected, kind) is True:
            last_step_right += 1
        decision = verdict(every, expected, kind)
        if decision is True:
            right += 1
        elif decision is False:
            wrong += 1
            misses.append((found.group(1), expected, every))
        else:
            undecided += 1

    decided = right + wrong
    print(f"steps targets in the training data: {total}")
    print(f"templates this script can solve:    {solvable}"
          f"  ({100 * solvable / total:.0f}% of them)")
    print(f"decided:                            {decided}")
    print(f"  correct:                          {right}"
          + (f"  ({100 * right / decided:.0f}% of decided)" if decided else ""))
    print(f"  wrong:                            {wrong}")
    print(f"undecidable — this script's limit, not the data's:  {undecided}")
    print()
    print(f"answer stated in the LAST step:     {last_step_right}"
          + (f"  ({100 * last_step_right / decided:.0f}% of decided)" if decided else ""))
    print("  the prompt asks for it there. Where it is not, the teacher has")
    print("  appended a verification step, and a consumer that reads the last")
    print("  step gets the check rather than the conclusion.")
    if misses:
        print("\nevery disagreement — problem | correct | target's last step")
        for problem, expected, got in misses:
            print(f"  {problem}  |  {expected}  |  {got}")


if __name__ == "__main__":
    main()
