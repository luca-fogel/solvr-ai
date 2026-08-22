#!/usr/bin/env bash
# Train to a target iteration count, surviving Metal's interruptions.
#
# macOS ends GPU command buffers that block the display too long
# (kIOGPUCommandBufferCallbackErrorImpactingInteractivity). Gradient accumulation
# made it rare rather than immediate -- the run reached iteration 125 instead of 1
# -- but rare is not never, and it is a platform behaviour rather than a bug in
# the training. Waiting for a configuration that never trips it is a worse use of
# time than making a trip cost nothing.
#
# So: checkpoint every 25 iterations, and on a crash resume from the last one with
# the remaining iteration count. Progress is cumulative across restarts and the
# log records every attempt.
#
#   tools/finetune/train.sh [target-iters] [max-attempts]
set -uo pipefail
cd "$(dirname "$0")/../.."

TARGET="${1:-600}"
MAX_ATTEMPTS="${2:-12}"
CONFIG=tools/finetune/lora-qwen3-4b.yaml
ADAPTER=tools/finetune/adapters/adapters.safetensors
LOG=/tmp/lora-train.log
LORA="$HOME/.venvs/mlx/bin/mlx_lm.lora"

completed() {  # cumulative across attempts -- see progress.py for why
  python3 tools/finetune/progress.py "$LOG" 2>/dev/null || echo 0
}

: > "$LOG"
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  DONE=$(completed); DONE=${DONE:-0}
  REMAINING=$(( TARGET - DONE ))
  if [ "$REMAINING" -le 0 ]; then
    echo "=== reached $DONE of $TARGET iterations ===" | tee -a "$LOG"
    exit 0
  fi

  echo "=== attempt $attempt: $DONE done, $REMAINING to go ===" | tee -a "$LOG"
  if [ -f "$ADAPTER" ] && [ "$DONE" -gt 0 ]; then
    "$LORA" --config "$CONFIG" --train --iters "$REMAINING" \
            --resume-adapter-file "$ADAPTER" >> "$LOG" 2>&1
  else
    "$LORA" --config "$CONFIG" --train --iters "$REMAINING" >> "$LOG" 2>&1
  fi

  if [ $? -eq 0 ]; then
    echo "=== training finished cleanly at attempt $attempt ===" | tee -a "$LOG"
    exit 0
  fi
  if ! grep -q 'ImpactingInteractivity' <(tail -40 "$LOG"); then
    echo "=== stopped for a reason that is not the Metal interruption ===" | tee -a "$LOG"
    tail -20 "$LOG"
    exit 1
  fi
  # Cool off before resuming. Throughput fell from 252 to 185 tokens/sec over the
  # course of the run, and the interactivity deadline is a *time* limit -- so a
  # throttled GPU trips it doing exactly the work that passed when the machine was
  # cold. Retrying instantly spends another attempt at the worst possible moment.
  echo "--- Metal interrupted it; cooling 90s, then resuming ---" | tee -a "$LOG"
  sleep 90
done
echo "=== gave up after $MAX_ATTEMPTS attempts ===" | tee -a "$LOG"
exit 1
