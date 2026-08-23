#!/usr/bin/env bash
# Measure the fine-tuned adapter against the base model on the full problem set.
#
# Sequential, not parallel, and one server at a time: training and serving contend
# for the same GPU, and two servers would contend with each other. The whole point
# of the numbers is that they are comparable, which they are not if one arm ran
# against a throttled machine.
#
#   tools/finetune/compare.sh [problem-limit]
set -euo pipefail
cd "$(dirname "$0")/../.."

LIMIT="${1:-43}"
BASE_MODEL=mlx-community/Qwen3-4B-4bit
PORT=8131
MLX="$HOME/.venvs/mlx/bin"

serve() {  # $1 = extra args
  pkill -f mlx_lm.server 2>/dev/null || true
  sleep 3
  nohup $MLX/mlx_lm.server --model "$BASE_MODEL" --host 127.0.0.1 --port "$PORT" \
    --chat-template-args '{"enable_thinking": false}' $1 \
    > /tmp/serve.log 2>&1 &
  until curl -s -m 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; do sleep 5; done
}

run() {  # $1 = output name
  (cd Packages/SolvrCore && swift run solvr-eval --backend local \
     --base-url "http://127.0.0.1:$PORT" --model "$BASE_MODEL" \
     --limit "$LIMIT" --max-tokens 1200 --out "$OLDPWD/$1.jsonl") 2>&1 | tail -2
}

echo "== arm 1 of 2: base model, no adapter"
serve ""
run eval-base

echo "== arm 2 of 2: base model + Solvr LoRA"
serve "--adapter-path tools/finetune/adapters"
run eval-tuned

pkill -f mlx_lm.server 2>/dev/null || true

# The two arms serve the same model name, so label them by which file they are.
python3 - <<'PY'
import json, pathlib
for name, label in [("eval-tuned", "local/qwen3-4b+solvr-lora"),
                    ("eval-base",  "local/qwen3-4b-base")]:
    p = pathlib.Path(f"{name}.jsonl")
    rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
    for r in rows:
        r["backend"] = label
    p.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
PY

for f in eval-base eval-tuned; do
  node tools/eval/latex_check.mjs "$f.jsonl" > "/tmp/$f.lx.jsonl" 2>"/tmp/$f.lx.err"
  "$HOME/.venvs/solvr-eval/bin/python" tools/eval/grade_answers.py "/tmp/$f.lx.jsonl" \
    > "$f.graded.jsonl" 2>"/tmp/$f.gr.err"
  grep -h 'answers:' "/tmp/$f.gr.err" | sed "s/^/$f /"
done

echo
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/report.py \
  eval-base.graded.jsonl eval-tuned.graded.jsonl | tee docs/evaluation-local.md
echo
echo "written to docs/evaluation-local.md"
