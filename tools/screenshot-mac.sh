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

# 12s was not enough. The step maths renders in WKWebViews, and a capture taken
# before they paint gives grey placeholder boxes where the LaTeX should be --
# which is what shipped in the committed screenshot for a while.
sleep 25

osascript -e 'tell application id "'"$BUNDLE_ID"'" to activate' 2>/dev/null || true
sleep 2

# Capture the WINDOW, not a screen rectangle.
#
# This used to be `screencapture -R <bounds>`, which captures a region of the
# display -- so anything floating over the app landed in the committed image. It
# did: a terminal window ended up covering half of docs/images/macos.png in the
# published README. `-l <windowID>` captures the window's own surface and cannot
# pick up an overlap.
WID="$(swift tools/window-id.swift "solvr.ai")"
echo "==> window id $WID"
screencapture -x -o -l "$WID" docs/images/macos.png
echo "    docs/images/macos.png"

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
defaults delete "$BUNDLE_ID" SolvrDemo 2>/dev/null || true
defaults delete "$BUNDLE_ID" SolvrScreen 2>/dev/null || true
