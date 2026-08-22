#!/usr/bin/env bash
# Re-run the (problem, surface) pairs that failed to decode.
#
# The first run predated LLMJSON.decodeList, which accepts an array however the
# model wrapped it. The failures were therefore concentrated entirely in the three
# array surfaces -- lesson, the one object surface, did not fail once -- so they
# are recoverable rather than lost, and re-running them also tests the fix against
# real traffic instead of only against fixtures.
#
#   tools/finetune/recover.sh <distill-stderr-log> <raw.jsonl to append to>
set -euo pipefail
cd "$(dirname "$0")/../.."

LOG="${1:-/tmp/distill-run.err}"
RAW="${2:-tools/finetune/data/raw.jsonl}"
: "${MOONSHOT_API_KEY:?export it first: set -a; . ~/.config/solvr/kimi.env; set +a}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for SURFACE in steps formulas videos lesson; do
  # The problem ids that failed on this surface, deduplicated.
  IDS=$(tr '\r' '\n' < "$LOG" | grep -oE "gen-[0-9]+/$SURFACE" | cut -d/ -f1 | sort -u)
  [ -z "$IDS" ] && continue
  COUNT=$(printf '%s\n' "$IDS" | wc -l | tr -d ' ')
  echo "== $SURFACE: $COUNT problems to retry"

  python3 - "$WORK/$SURFACE.json" <<PY
import json, sys, pathlib
ids = set("""$IDS""".split())
src = json.loads(pathlib.Path("tools/finetune/problems.json").read_text())
keep = [p for p in src["problems"] if p["id"] in ids]
pathlib.Path(sys.argv[1]).write_text(json.dumps({"problems": keep}))
PY

  (cd Packages/SolvrCore && swift run solvr-distill \
      --teacher openai --base-url https://api.moonshot.ai/v1 \
      --key-env MOONSHOT_API_KEY --model kimi-k3 \
      --problems "$WORK/$SURFACE.json" \
      --out "$WORK/$SURFACE.jsonl" \
      --surfaces "$SURFACE" --concurrency 16 --confirm-spend) \
    2>&1 | grep -E 'written|failed|tokens' | sed 's/^/   /'

  if [ -s "$WORK/$SURFACE.jsonl" ]; then
    cat "$WORK/$SURFACE.jsonl" >> "$RAW"
  fi
done

echo
echo "recovered into $RAW — now $(wc -l < "$RAW" | tr -d ' ') examples total"
