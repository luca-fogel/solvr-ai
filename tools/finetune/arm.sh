#!/usr/bin/env bash
# One evaluation arm: serve a model and measure it on the problem set.
#
#   tools/finetune/arm.sh <output-name> <label> <model-path-or-repo> [limit]
#
# Takes a model rather than an adapter, deliberately. mlx_lm.server 0.31.3 accepts
# --adapter-path and silently ignores it: server.py resolves model_path through
# _model_map and *then* looks the adapter up under the resolved name, while the map
# is keyed by the pre-resolution "default_model" -- so the lookup always misses.
# Verified against a running server: the CLI flag produced base-identical output
# while passing "adapters" in the request body changed it. Fusing sidesteps the
# broken path entirely and is what shipping would do anyway.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="${1:?output name}"; LABEL="${2:?label}"; MODEL="${3:?model}"; LIMIT="${4:-43}"
PORT=8131

PID=$(tools/finetune/serve-exclusively.sh "$PORT" "$MODEL" "")
FP=$(python3 tools/finetune/fingerprint.py "http://127.0.0.1:$PORT" "$MODEL")
echo "  serving $MODEL as pid $PID · fingerprint $FP"
echo "$FP  $OUT  $MODEL" >> /tmp/arm-fingerprints.txt

(cd Packages/SolvrCore && swift run solvr-eval --backend local \
   --base-url "http://127.0.0.1:$PORT" --model "$MODEL" \
   --limit "$LIMIT" --max-tokens 1200 --out "$OLDPWD/$OUT.jsonl") 2>&1 | tail -2

pkill -f mlx_lm.server 2>/dev/null || true

python3 - "$OUT" "$LABEL" <<'PY'
import json, pathlib, sys
p = pathlib.Path(f"{sys.argv[1]}.jsonl")
rows = [json.loads(l) for l in p.read_text().splitlines() if l.strip()]
for r in rows:
    r["backend"] = sys.argv[2]
p.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
print(f"  {len(rows)} records labelled {sys.argv[2]}")
PY

node tools/eval/latex_check.mjs "$OUT.jsonl" > "/tmp/$OUT.lx.jsonl" 2>"/tmp/$OUT.lx.err"
"$HOME/.venvs/solvr-eval/bin/python" tools/eval/grade_answers.py "/tmp/$OUT.lx.jsonl" \
  > "$OUT.graded.jsonl" 2>"/tmp/$OUT.gr.err"
grep -h 'answers:' "/tmp/$OUT.gr.err" | sed "s/^/  $OUT /"
