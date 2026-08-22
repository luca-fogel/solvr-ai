#!/bin/bash
# Regenerate every screenshot in docs/images/ from a simulator, in demo mode.
#
# Deterministic on purpose: each screen is a separate launch with
# `-SolvrDemo YES -SolvrScreen <name>`, so nothing depends on synthesising taps
# at measured pixel coordinates, and anyone can reproduce the exact images in
# the README with one command.
#
#   ./tools/screenshots.sh [device-name]
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro}"
BUNDLE_ID="Lulu.solvr-ai"
OUT="docs/images"
DD="$(mktemp -d)/dd"
mkdir -p "$OUT"

echo "==> building for $DEVICE"
xcodebuild -project solvr.ai.xcodeproj -scheme solvr.ai \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DD" build >/dev/null

APP="$(find "$DD/Build/Products" -name 'solvr.ai.app' -maxdepth 3 | head -1)"
[ -n "$APP" ] || { echo "no app bundle built"; exit 1; }

UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')"
[ -n "$UDID" ] || { echo "no available simulator called '$DEVICE'"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

# Light status bar, plausible clock, full battery: a screenshot with 14% battery
# and three bars of signal reads as a photo of a phone, not as a product shot.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 || true

xcrun simctl install "$UDID" "$APP"

for screen in home steps lesson formulas videos chat history settings; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # A fresh container per shot, so History is seeded from empty every time.
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -SolvrDemo YES -SolvrScreen "$screen" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$OUT/$screen.png" >/dev/null
  echo "    $OUT/$screen.png"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "==> done. $(ls "$OUT"/*.png | wc -l | tr -d ' ') screenshots in $OUT"
