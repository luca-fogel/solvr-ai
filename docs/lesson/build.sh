#!/usr/bin/env bash
# Render the lesson to PDF.
#
# Chrome headless rather than a LaTeX toolchain, for one reason: the document
# typesets its mathematics with the same vendored KaTeX the app ships, so what
# the PDF shows is what the app would draw. No network, no second renderer to
# disagree with the first.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
  --virtual-time-budget=6000 \
  --print-to-pdf="$PWD/solvr-cs-lesson.pdf" \
  "file://$PWD/lesson.html" 2>/dev/null
echo "wrote solvr-cs-lesson.pdf"
