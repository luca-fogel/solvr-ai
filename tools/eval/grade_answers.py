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
import ast
import io
import json
import re
import sys
import tokenize
import warnings

warnings.filterwarnings("ignore")

import sympy
from sympy.parsing.latex import parse_latex

MAX_EXPRESSION_LENGTH = 2048
MAX_EXPRESSION_NODES = 256


def arithmetic_expression(text):
    """Build symbolic arithmetic from an allowlisted AST; never evaluate Python."""
    # Parenthesis juxtaposition means multiplication in model math: (x-2)(x-3)
    # and e^x (x+1). Rewrite tokens before parsing, rather than letting Python's
    # call precedence reinterpret the latter as e**(x*(x+1)). Function calls
    # remain restricted to the allowlist below.
    tokens = []
    previous = None
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.string == "(" and previous is not None:
            kind, value = previous
            variable = kind == tokenize.NAME and (value in {"pi", "E"} or
                       (len(value) == 1 and value.isalpha()))
            if kind == tokenize.NUMBER or value == ")" or variable:
                tokens.append((tokenize.OP, "*"))
        tokens.append((token.type, token.string))
        if token.type not in {tokenize.NL, tokenize.NEWLINE, tokenize.ENDMARKER}:
            previous = (token.type, token.string)
    source = tokenize.untokenize(tokens).replace("^", "**")
    tree = ast.parse(source, mode="eval")
    if sum(1 for _ in ast.walk(tree)) > MAX_EXPRESSION_NODES:
        raise ValueError("expression is too complex")
    functions = {name: getattr(sympy, name) for name in
                 ("sin", "cos", "tan", "sec", "csc", "cot", "log", "exp",
                  "sqrt", "asin", "acos", "atan")}
    functions.update(ln=sympy.log, abs=sympy.Abs)
    constants = {"pi": sympy.pi, "e": sympy.E, "E": sympy.E}

    def convert(node, depth=0):
        if depth > 32:
            raise ValueError("expression is too deep")
        child = lambda n: convert(n, depth + 1)
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            literal = ast.get_source_segment(source, node)
            if len(literal) > 100:
                raise ValueError("number is too large")
            return sympy.Integer(node.value) if type(node.value) is int else sympy.Float(literal)
        if isinstance(node, ast.Name) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,31}", node.id):
            return constants.get(node.id, sympy.Symbol(node.id))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = child(node.operand)
            return value if isinstance(node.op, ast.UAdd) else -value
        if isinstance(node, ast.BinOp):
            left, right = child(node.left), child(node.right)
            if isinstance(node.op, ast.Add): return sympy.Add(left, right, evaluate=False)
            if isinstance(node.op, ast.Sub): return sympy.Add(left, -right, evaluate=False)
            if isinstance(node.op, ast.Mult): return sympy.Mul(left, right, evaluate=False)
            if isinstance(node.op, ast.Div): return sympy.Mul(left, sympy.Pow(right, -1, evaluate=False), evaluate=False)
            if isinstance(node.op, ast.Pow):
                # Avoid evaluating towers or unbounded numeric exponents.
                if isinstance(node.right, ast.BinOp):
                    raise ValueError("compound powers are unsupported")
                if right.is_number and abs(right) > 1000:
                    raise ValueError("power is too large")
                return sympy.Pow(left, right, evaluate=False)
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id in functions and not node.keywords and len(node.args) == 1):
            return functions[node.func.id](child(node.args[0]), evaluate=False)
        raise ValueError("unsupported arithmetic syntax")

    return convert(tree.body)


def clean(tex: str) -> str:
    """Strip the presentation and keep the mathematics."""
    s = tex.strip()
    s = s.strip("$")
    s = s.removeprefix(r"\(").removesuffix(r"\)")
    s = re.sub(r"\\(left|right)\b", "", s)
    s = re.sub(r"\\[,;!qquad]+", " ", s)
    s = re.sub(r"\\text\{[^{}]*\}", "", s)
    # A final line is often written as "= 1" or "x = 1"; the answer is the tail.
    if "=" in s:
        s = s.split("=")[-1]
    s = s.strip()
    if s.startswith(r"\boxed{") and s.endswith("}"):
        s = s[len(r"\boxed{"):-1]
    return s.strip().rstrip(".")


# Answers arrive in three shapes the old grader could not read, and all three
# were counted as `undecidable` -- which reads like a model failure and is not
# one. Every one of these came out of a real on-device run:
#
#   "The area of the triangle is 30 square units."   answer wrapped in a sentence
#   "x = 2 or x = 3"                                 more than one root
#   "\theta = \pi/6, 5\pi/6"                        more than one root, comma-separated
#
# The rule stays what it was: never call something correct that is not. Splitting
# and prose-extraction only ever produce *candidates*, and each candidate is still
# compared symbolically.

SPLIT = re.compile(r"[,;]|\bor\b|\band\b", re.IGNORECASE)


def parts(tex: str) -> list:
    """One answer, or the several an answer may contain."""
    # The app sets a joining word as text -- "x = 2 \text{ or } x = 3" -- so
    # that it renders as a word. Splitting on "or" first left "2 \text{" as a
    # candidate and graded a correct pair of roots wrong. Unwrap before
    # splitting; `normalise` already discards any \text{} that survives.
    tex = re.sub(r"\\text\{([^{}]*)\}", r" \1 ", tex)
    pieces = [p.strip() for p in SPLIT.split(tex) if p.strip()]
    return pieces if len(pieces) > 1 else [tex]


def from_prose(text: str) -> str:
    """The mathematics inside a sentence, if there is exactly one candidate.

    Deliberately timid. It takes the last `= <value>` or the last number in the
    sentence, and only when the sentence reads like an answer being stated. A
    cleverer extractor would start inventing agreement.
    """
    _, separator, tail = text.rpartition("=")
    if separator and tail.strip():
        return tail.strip().removesuffix(".").rstrip()
    numbers = re.findall(r"-?\d+(?:\.\d+)?(?:/\d+)?", text)
    return numbers[-1] if numbers else ""


# A word of three or more letters that is not a function name is a word, not a
# product of single-letter variables. sympify will happily read "The area of the
# triangle is 30 square units" as T*h*e*a*r*e*a*... and return an expression, so
# "did it parse?" is not a usable test for whether a string is mathematics.
FUNCTIONS = {"sin", "cos", "tan", "sec", "csc", "cot", "log", "ln", "exp",
             "sqrt", "pi", "theta", "asin", "acos", "atan", "abs", "det"}
WORD = re.compile(r"[A-Za-z]{3,}")


def looks_like_prose(text: str) -> bool:
    words = [w.lower() for w in WORD.findall(re.sub(r"\\[a-zA-Z]+", " ", text))]
    return len([w for w in words if w not in FUNCTIONS]) >= 2


def to_expr(tex: str):
    if not isinstance(tex, str) or len(tex) > MAX_EXPRESSION_LENGTH:
        return None
    s = clean(tex)
    if not s:
        return None
    # A backslash means the model wrote LaTeX; anything else is likelier to be
    # sympy's own syntax, where `pi` is pi. Reading "pi/6" as LaTeX gives p*i/6,
    # which then compares unequal to the same answer written the other way.
    latex_first = "\\" in s
    try:
        if latex_first:
            expr = parse_latex(s, strict=True)
        else:
            try:
                expr = arithmetic_expression(s)
            except SyntaxError:
                # Preserve implicit multiplication such as 2x. The LaTeX parser
                # constructs symbolic objects; it does not evaluate Python.
                expr = parse_latex(s, strict=True)
        if sum(1 for _ in sympy.preorder_traversal(expr)) > MAX_EXPRESSION_NODES:
            return None
        # parse_latex reads constants as symbols: normalize e and pi so they
        # compare equally to the same constants in arithmetic notation.
        free = getattr(expr, "free_symbols", set())
        for name, constant in (("e", sympy.E), ("pi", sympy.pi)):
            symbol = sympy.Symbol(name)
            if symbol in free:
                expr = expr.subs(symbol, constant)
        return expr
    except Exception:
        return None


def expressions(text: str) -> list:
    """Every expression an answer string yields, prose included."""
    # Prose first when it reads as prose. Otherwise sympify "parses" the
    # sentence into a product of its letters and the comparison is against
    # nonsense rather than against the answer.
    if not isinstance(text, str) or len(text) > MAX_EXPRESSION_LENGTH:
        return []
    if looks_like_prose(text):
        extracted = from_prose(text)
        if extracted:
            single = to_expr(extracted)
            if single is not None:
                return [single]
    found = [e for e in (to_expr(p) for p in parts(text)) if e is not None]
    if found:
        return found
    extracted = from_prose(text)
    if extracted:
        single = to_expr(extracted)
        if single is not None:
            return [single]
    return []


def same(a, b) -> bool:
    try:
        return sympy.simplify(a - b) == 0
    except Exception:
        return False


def grade(record):
    """True, False, or None for 'could not decide -- hand-check this one'."""
    answer = record.get("finalAnswer")
    if not answer:
        return None, "no final answer in the response"

    got = expressions(answer)
    if not got:
        return None, "could not parse the answer"

    expected_numeric = record.get("expectedNumeric")
    if expected_numeric is not None:
        for candidate in got:
            try:
                value = complex(sympy.N(candidate))
            except Exception:
                continue
            if abs(value.imag) > 1e-9:
                continue
            if abs(value.real - float(expected_numeric)) < 1e-6:
                return True, f"{value.real} vs {expected_numeric}"
        return False, f"{[str(g) for g in got]} vs {expected_numeric}"

    want = expressions(record.get("expectedAnswer", ""))
    if not want:
        return None, "could not parse the expected answer"

    # Every expected root has to appear, and the answer may not invent one. A
    # solution that finds one of two roots is not a right answer.
    if all(any(same(g, w) for g in got) for w in want) and len(got) >= len(want):
        return True, "every expected value present"
    if len(got) == 1 and len(want) == 1:
        return False, f"{got[0]} != {want[0]}"
    return False, f"{[str(g) for g in got]} != {[str(w) for w in want]}"


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
