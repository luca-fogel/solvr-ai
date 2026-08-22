#!/usr/bin/env bash
# One evaluation arm: serve a model (optionally with an adapter) and measure it.
#
# Split out of compare.sh so a third arm can be added without re-running the
# first two. Arms must run one at a time -- two servers, or a server plus a
# trainer, contend for the same GPU and the numbers stop being comparable.
#
#   tools/eval/arm.sh <output-name> <label> [adapter-path] [limit]
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="${1:?output name, e.g. eval-525}"
LABEL="${2:?label for the report, e.g. local/qwen3-4b+lora@525}"
ADAPTER="${3:-}"
LIMIT="${4:-43}"
BASE_MODEL=mlx-community/Qwen3-4B-4bit
PORT=8131
MLX="$HOME/.venvs/mlx/bin"

pkill -f mlx_lm.server 2>/dev/null || true
sleep 3
ARGS=""
[ -n "$ADAPTER" ] && ARGS="--adapter-path $ADAPTER"
nohup $MLX/mlx_lm.server --model "$BASE_MODEL" --host 127.0.0.1 --port "$PORT" \
  --chat-template-args '{"enable_thinking": false}' $ARGS > /tmp/serve.log 2>&1 &
until curl -s -m 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; do sleep 5; done
echo "serving${ADAPTER:+ with adapter $ADAPTER}"

(cd Packages/SolvrCore && swift run solvr-eval --backend local \
   --base-url "http://127.0.0.1:$PORT" --model "$BASE_MODEL" \
   --limit "$LIMIT" --max-tokens 1200 --out "$OLDPWD/$OUT.jsonl") 2>&1 | tail -2

pkill -f mlx_lm.server 2>/dev/null || true

python3 - "$OUT" "$LABEL" <<'PY'
import json, pathlib, sys
p = pathlib.Path(f"{sys.argv[1]}.jsonl")
rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
for r in rows:
    r["backend"] = sys.argv[2]
p.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
print(f"{len(rows)} records labelled {sys.argv[2]}")
PY

node tools/eval/latex_check.mjs "$OUT.jsonl" > "/tmp/$OUT.lx.jsonl" 2>"/tmp/$OUT.lx.err"
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/grade_answers.py "/tmp/$OUT.lx.jsonl" \
  > "$OUT.graded.jsonl" 2>"/tmp/$OUT.gr.err"
grep -h 'answers:\|latex strings' "/tmp/$OUT.gr.err" "/tmp/$OUT.lx.err" | sed "s/^/$OUT: /"
