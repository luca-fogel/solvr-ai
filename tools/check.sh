#!/usr/bin/env bash
#
# Everything CI checks, runnable on your own machine with no network and no
# service account.
#
# This used to live only in .github/workflows/ci.yml, which meant the answer to
# "is this repository honest?" was a service's to give. It is a script now, and
# the workflow calls it. Nothing here needs a token, an API key or a runner.
#
# What is deliberately NOT here: the two xcodebuild lines. They need Xcode 26 and
# the iOS 26 SDK, and a check that cannot run on a stock machine is a check that
# quietly stops being run. The README states them for a local build.
set -euo pipefail

cd "$(dirname "$0")/.."
fail=0
note() { printf '\n\033[1m%s\033[0m\n' "$1"; }

note "SolvrCore suite"
swift test --package-path Packages/SolvrCore 2>&1 | tee /tmp/solvr-test.log | tail -3

# The README quotes a test count. It was wrong by half once, so the number is
# asserted against the run rather than trusted to be remembered.
note "README test count matches the run"
actual=$(grep -oE 'Test run with [0-9]+ tests' /tmp/solvr-test.log | grep -oE '[0-9]+' | head -1)
# Every "<n> tests" in the README, not just the one this check was written
# for: the count appeared twice and only one of them was ever asserted, so the
# other sat wrong through two releases.
echo "run: ${actual}"
if [ -z "$actual" ]; then
  echo "could not read a test count from the run" >&2
  fail=1
else
  for declared in $(grep -oE '[0-9]+ tests' README.md | grep -oE '^[0-9]+'); do
    if [ "$declared" != "$actual" ]; then
      echo "MISMATCH: README says ${declared}, the run reported ${actual}" >&2
      fail=1
    fi
  done
  echo "README mentions: $(grep -coE '[0-9]+ tests' README.md), all matching"
fi

# docs/evaluation-local.md is report.py's stdout and nothing else. If a number in
# it is ever edited by hand, or the records change without the document being
# regenerated, this diff fails. Stdlib only, so nothing to install.
note "docs/evaluation-local.md regenerates from docs/eval-records/"
if python3 tools/eval/report.py docs/eval-records/*.graded.jsonl | diff - docs/evaluation-local.md; then
  echo "identical"
else
  fail=1
fi

note "Every record is parseable and accounted for"
python3 - <<'PY' || fail=1
import glob, json
recs = [json.loads(l) for f in glob.glob("docs/eval-records/*.graded.jsonl") for l in open(f)]
assert len(recs) == 387, len(recs)
assert len({r["problemId"] for r in recs}) == 43
assert len({r["backend"] for r in recs}) == 3
print(f"{len(recs)} records, 43 problems, 3 arms")
PY

# The app is supposed to be unable to phone home. That is a property worth
# testing rather than asserting in a README, because it is one careless
# URLSession away from being false.
note "No network client, no credential store, no vendor endpoint"
if grep -rnE 'URLSession|api\.anthropic|cdn\.jsdelivr|img\.youtube|x-api-key|ANTHROPIC_API_KEY|SecItemAdd' \
     --include='*.swift' solvr.ai Packages/SolvrCore/Sources \
   | grep -v 'LegacyCredentialPurge.swift' \
   | grep -v '^\S*: *//' ; then
  echo "the app reaches the network or stores a credential" >&2
  fail=1
else
  echo "none"
fi

# App Store Connect rejects a marketing icon with an alpha channel, and Xcode
# does not warn -- the failure arrives after the upload, which is the most
# expensive moment to learn it. One sips call catches it here instead.
note "App icon is opaque"
icon_fail=0
for png in solvr.ai/Assets.xcassets/AppIcon.appiconset/*.png; do
  if sips -g hasAlpha "$png" 2>/dev/null | grep -q 'hasAlpha: yes'; then
    echo "$(basename "$png") has an alpha channel" >&2
    icon_fail=1
  fi
done
if [ "$icon_fail" = 0 ]; then
  echo "$(ls solvr.ai/Assets.xcassets/AppIcon.appiconset/*.png | wc -l | tr -d ' ') icons, none transparent"
else
  fail=1
fi

# The privacy manifest is required at submission and easy to delete by accident.
note "Privacy manifest present and well-formed"
if plutil -lint solvr.ai/PrivacyInfo.xcprivacy >/dev/null 2>&1; then
  echo "PrivacyInfo.xcprivacy parses"
else
  echo "PrivacyInfo.xcprivacy is missing or malformed" >&2
  fail=1
fi

# Demo mode answers every question with the same fixture. It must not be
# reachable from a Release build -- not off by default, not reachable.
note "No demo branch in the release path"
python3 - <<'PY' || fail=1
import sys
src = open("solvr.ai/Services/ProviderFactory.swift").read().splitlines()
depth, guarded, seen = 0, True, False
for line in src:
    stripped = line.strip()
    if stripped.startswith("#if DEBUG"):
        depth += 1
    elif stripped.startswith("#endif") and depth:
        depth -= 1
    if "DemoMode.isEnabled" in line:
        seen = True
        if depth == 0:
            guarded = False
if not seen:
    print("no demo branch at all")
elif guarded:
    print("demo branch is inside #if DEBUG; release resolves to the on-device model")
else:
    sys.exit("ProviderFactory consults demo mode outside a DEBUG guard")
PY

if [ "$fail" = 0 ]; then note "all checks passed"; else note "FAILED"; fi
exit "$fail"
