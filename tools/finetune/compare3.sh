#!/usr/bin/env bash
# Three arms, sequentially, refusing to report if two served the same weights.
set -euo pipefail
cd "$(dirname "$0")/../.."
LIMIT="${1:-43}"
rm -f /tmp/arm-fingerprints.txt

tools/finetune/arm.sh eval-base  "local/qwen3-4b-base"     mlx-community/Qwen3-4B-4bit    "$LIMIT"
tools/finetune/arm.sh eval-525   "local/qwen3-4b+lora@525" "$HOME/models/solvr-qwen3-4b-525" "$LIMIT"
tools/finetune/arm.sh eval-tuned "local/qwen3-4b+lora@600" "$HOME/models/solvr-qwen3-4b-600" "$LIMIT"

echo
echo "=== weight fingerprints ==="
cat /tmp/arm-fingerprints.txt
UNIQ=$(awk '{print $1}' /tmp/arm-fingerprints.txt | sort -u | wc -l | tr -d ' ')
if [ "$UNIQ" -lt 3 ]; then
  echo "REFUSING TO REPORT: only $UNIQ distinct fingerprints across 3 arms." >&2
  exit 1
fi
echo "  three distinct fingerprints — the arms served three different models."
echo
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/report.py \
  eval-base.graded.jsonl eval-525.graded.jsonl eval-tuned.graded.jsonl \
  | tee docs/evaluation-local.md
