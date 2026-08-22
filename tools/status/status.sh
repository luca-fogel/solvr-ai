#!/usr/bin/env bash
# Status of the distillation, training and evaluation runs.
#   tools/status/status.sh            one-shot terminal snapshot
#   tools/status/status.sh --html     also write docs/run-status.html
#   tools/status/status.sh --watch    refresh terminal + html every 10s
exec python3 "$(dirname "$0")/status.py" "$@"
