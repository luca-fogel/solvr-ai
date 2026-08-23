#!/usr/bin/env bash
# Wait for the current evaluation to finish, then run one more arm and report.
#
# A script file rather than an inline `bash -c`, because the previous inline
# version contained the string it was grepping for -- so `pgrep -f solvr-eval`
# matched the waiter's own command line and it would have waited forever. A
# process that looks for itself never finds nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."

# Match the compiled binary path, which no wrapper's command line contains.
while pgrep -f 'debug/solvr-eval' >/dev/null 2>&1 || pgrep -f 'mlx_lm.server' >/dev/null 2>&1; do
  sleep 20
done

echo "=== earlier arms finished; running the 525 checkpoint ==="
tools/finetune/arm.sh eval-525 "local/qwen3-4b+lora@525" tools/finetune/adapters-525 43

echo "=== all three arms done ==="
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/report.py \
  eval-base.graded.jsonl eval-tuned.graded.jsonl eval-525.graded.jsonl \
  | tee docs/evaluation-local.md
