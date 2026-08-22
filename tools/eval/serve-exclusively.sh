#!/usr/bin/env bash
# Start an mlx_lm.server that is definitely OUR server, and definitely the only one.
#
# The naive version -- pkill, sleep, then poll the port with curl -- produced three
# evaluation arms with byte-identical output, because mlx_lm.server binds its port
# only *after* loading the weights. So: pkill signals the old server, which takes
# its time dying; the new one starts, finds the port still held, and exits; the
# curl poll then succeeds against the OLD server; and the arm silently measures
# the previous arm's weights. Three arms, one model, identical numbers, and a
# comparison that looked plausible and meant nothing.
#
# The fix is to wait for the port to be genuinely free, then to confirm the
# listener is the process we started.
#
#   serve-exclusively.sh <port> <model> [adapter-path]   -> prints the server PID
set -euo pipefail
PORT="${1:?port}"; MODEL="${2:?model}"; ADAPTER="${3:-}"
MLX="$HOME/.venvs/mlx/bin"

pkill -f mlx_lm.server 2>/dev/null || true
for _ in $(seq 1 40); do
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
  sleep 1
done
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  pkill -9 -f mlx_lm.server 2>/dev/null || true
  sleep 3
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "port $PORT is still held; refusing to start and report against someone else's server" >&2
  exit 1
fi

ARGS=(--model "$MODEL" --host 127.0.0.1 --port "$PORT"
      --chat-template-args '{"enable_thinking": false}')
[ -n "$ADAPTER" ] && ARGS+=(--adapter-path "$ADAPTER")
nohup "$MLX/mlx_lm.server" "${ARGS[@]}" > "/tmp/serve-$PORT.log" 2>&1 &
PID=$!

for _ in $(seq 1 120); do
  if curl -s -m 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    OWNER=$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1)
    # The listener must be the process we launched, or a child of it.
    if [ "$OWNER" = "$PID" ] || [ "$(ps -o ppid= -p "${OWNER:-0}" 2>/dev/null | tr -d ' ')" = "$PID" ]; then
      echo "$PID"; exit 0
    fi
    echo "port $PORT is served by pid $OWNER, not the server we started ($PID)" >&2
    exit 1
  fi
  kill -0 "$PID" 2>/dev/null || { echo "server died during load; see /tmp/serve-$PORT.log" >&2; exit 1; }
  sleep 2
done
echo "server never came up" >&2; exit 1
