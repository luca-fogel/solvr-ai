#!/usr/bin/env bash
# Keep docs/run-status.html current for a while, independent of any one run.
#
# The previous watcher followed the training process and died with it, leaving a
# stale page at exactly the moment there was something worth reading.
set -euo pipefail
cd "$(dirname "$0")/../.."
MINUTES="${1:-180}"
END=$(( $(date +%s) + MINUTES * 60 ))
while [ "$(date +%s)" -lt "$END" ]; do
  python3 tools/status/status.py --html >/dev/null 2>&1 || true
  sleep 10
done
