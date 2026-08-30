#!/usr/bin/env bash
# Every arm, sequentially, refusing to report if two of them served the same
# weights.
#
# Four now, not three. The published comparison measured the base model and two
# late checkpoints -- cumulative 525 and 600, both past two epochs -- and found
# the fine-tune a clear regression on maths correctness. The obvious question it
# could not answer is whether that is *training*, or whether it is *training for
# too long*: 600 iterations at an effective batch of four over 875 examples is
# about 2.7 epochs for a task that is teaching an output shape.
#
# Cumulative 225 is a little over one epoch and it survives on disk, so the
# question is answerable for the cost of one more arm. Which checkpoint file that
# is, is not something to guess -- mlx_lm restarts its counter on every resume
# and the filenames lie. See adapters-525/PROVENANCE.md.
#
#   tools/finetune/compare-arms.sh [limit]
set -euo pipefail
cd "$(dirname "$0")/../.."
LIMIT="${1:-43}"
rm -f /tmp/arm-fingerprints.txt

tools/finetune/arm.sh eval-base  "local/qwen3-4b-base"     mlx-community/Qwen3-4B-4bit        "$LIMIT"
tools/finetune/arm.sh eval-225   "local/qwen3-4b+lora@225" "$HOME/models/solvr-qwen3-4b-225" "$LIMIT"
tools/finetune/arm.sh eval-525   "local/qwen3-4b+lora@525" "$HOME/models/solvr-qwen3-4b-525" "$LIMIT"
tools/finetune/arm.sh eval-tuned "local/qwen3-4b+lora@600" "$HOME/models/solvr-qwen3-4b-600" "$LIMIT"

ARMS=4
echo
echo "=== weight fingerprints ==="
cat /tmp/arm-fingerprints.txt
UNIQ=$(awk '{print $1}' /tmp/arm-fingerprints.txt | sort -u | wc -l | tr -d ' ')
if [ "$UNIQ" -lt "$ARMS" ]; then
  echo "REFUSING TO REPORT: only $UNIQ distinct fingerprints across $ARMS arms." >&2
  exit 1
fi
echo "  $ARMS distinct fingerprints — the arms served $ARMS different models."
echo
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/report.py \
  eval-base.graded.jsonl eval-225.graded.jsonl \
  eval-525.graded.jsonl eval-tuned.graded.jsonl \
  | tee docs/evaluation-local.md
