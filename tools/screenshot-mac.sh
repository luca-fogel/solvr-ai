#!/bin/bash
# Capture the Mac Catalyst build, which is a different layout from iOS: a
# two-column split with the chat kept alongside the solution.
#
#   ./tools/screenshot-mac.sh
#
# Ad-hoc signed and run locally; no Developer Program membership needed.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="Lulu.solvr-ai"
DD="$(mktemp -d)/dd"

echo "==> building for Mac Catalyst"
xcodebuild -project solvr.ai.xcodeproj -scheme solvr.ai \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES build >/dev/null

APP="$(find "$DD/Build/Products" -name 'solvr.ai.app' -maxdepth 3 | head -1)"
[ -n "$APP" ] || { echo "no Catalyst app built"; exit 1; }

# Demo mode via defaults, since a Mac app takes no launch arguments from `open`.
defaults write "$BUNDLE_ID" SolvrDemo -bool YES
defaults write "$BUNDLE_ID" SolvrScreen -string steps

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
open "$APP"
sleep 12

BOUNDS=$(osascript -e 'tell application "System Events" to tell process "solvr.ai"
  set p to position of window 1
  set s to size of window 1
  return (item 1 of p as text) & "," & (item 2 of p as text) & "," & (item 1 of s as text) & "," & (item 2 of s as text)
end tell')
echo "==> window at $BOUNDS"
screencapture -x -R"$BOUNDS" docs/images/macos.png
echo "    docs/images/macos.png"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
defaults delete "$BUNDLE_ID" SolvrDemo 2>/dev/null || true
defaults delete "$BUNDLE_ID" SolvrScreen 2>/dev/null || true
