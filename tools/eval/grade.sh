#!/usr/bin/env bash
# Grade a raw eval run and print the report.
#
#   tools/eval/grade.sh eval-results.jsonl
#
# Kept as three steps on purpose: the requests are the expensive part, so
# grading and reporting must be re-runnable against a saved run without paying
# for it again.
set -euo pipefail
cd "$(dirname "$0")"

RAW="${1:?usage: grade.sh <results.jsonl>}"
RAW="$(cd "$(dirname "$RAW")" && pwd)/$(basename "$RAW")"
GRADED="${RAW%.jsonl}.graded.jsonl"

SYMPY_PY="${SYMPY_PY:-$HOME/.venvs/solvr-eval/bin/python}"
if [ ! -x "$SYMPY_PY" ]; then
  echo "no sympy interpreter at $SYMPY_PY" >&2
  echo "create one with: python3 -m venv ~/.venvs/solvr-eval && ~/.venvs/solvr-eval/bin/pip install sympy 'antlr4-python3-runtime==4.11'" >&2
  exit 1
fi
# Node resolves upwards, and the package.json that owns katex lives one level
# up in tools/ -- so checking for it beside this script reported it missing on a
# tree where it was installed and working.
if [ ! -d node_modules/katex ] && [ ! -d ../node_modules/katex ]; then
  echo "katex is not installed. run: (cd tools && npm install katex@0.16.21)" >&2
  exit 1
fi

node latex_check.mjs "$RAW" > "$GRADED.tmp"
"$SYMPY_PY" grade_answers.py "$GRADED.tmp" > "$GRADED"
rm -f "$GRADED.tmp"
echo "graded -> $GRADED" >&2
echo >&2
"$SYMPY_PY" report.py "$GRADED"
