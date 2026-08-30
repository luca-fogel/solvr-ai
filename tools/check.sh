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

# The same rule for the on-device arms, which live in a subdirectory so the
# corpus totals asserted below stay what they were.
note "docs/evaluation-samples.md regenerates from docs/eval-records/samples/"
if python3 tools/eval/report.py docs/eval-records/samples/*.graded.jsonl \
   | diff - docs/evaluation-samples.md; then
  echo "identical"
else
  fail=1
fi

# Same rule again for the camera arm, which lives in its own subdirectory so the
# corpus totals asserted below stay what they were.
note "docs/evaluation-camera.md regenerates from docs/eval-records/camera/"
if python3 tools/eval/report.py docs/eval-records/camera/*.graded.jsonl \
   | diff - docs/evaluation-camera.md; then
  echo "identical"
else
  fail=1
fi

# A camera fixture without ground truth beside it is a picture, not a
# measurement, and a manifest entry without its picture is a run that silently
# skips.
note "Every camera fixture has a manifest entry and vice versa"
python3 - <<'PY2' || fail=1
import json, pathlib
root = pathlib.Path("docs/fixtures/camera")
manifest = json.loads((root / "manifest.json").read_text())["fixtures"]
declared = {f["file"] for f in manifest}
present = {p.name for p in root.iterdir()
           if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic"}}
missing = declared - present
extra = present - declared
assert not missing, f"manifest names images that are not here: {sorted(missing)}"
assert not extra, f"images with no manifest entry: {sorted(extra)}"
for f in manifest:
    assert f.get("expectedText"), f"{f['id']} has no expectedText"
    assert f.get("answer") or f.get("expectUnreadable"), f"{f['id']} has no answer"
print(f"{len(manifest)} fixtures, each with an image and ground truth")
PY2

note "Every record is parseable and accounted for"
python3 - <<'PY' || fail=1
import glob, json
recs = [json.loads(l) for f in glob.glob("docs/eval-records/*.graded.jsonl") for l in open(f)]
assert len(recs) == 516, len(recs)
assert len({r["problemId"] for r in recs}) == 43
assert len({r["backend"] for r in recs}) == 4
# Every arm must have served different weights. Three arms once produced 129
# byte-identical responses because a port race left them all talking to one
# server, and the report looked entirely plausible.
answers = {b: tuple(sorted((r["problemId"], r["surface"], str(r.get("finalAnswer")))
                           for r in recs if r["backend"] == b))
           for b in {r["backend"] for r in recs}}
assert len(set(answers.values())) == 4, "two arms produced identical responses"
print(f"{len(recs)} records, 43 problems, 4 arms, none of them each other")
PY

# The app is supposed to be unable to phone home. That is a property worth
# testing rather than asserting in a README, because it is one careless
# URLSession away from being false.
#
# Scoped to what actually ships: the app target, and the SolvrCore *library* it
# links. Not `Sources/solvr-eval`, which is a command-line measurement tool that
# is never installed on a phone and which does contain an HTTP client -- it is
# the only way to drive a self-hosted model, and the fine-tune comparison this
# repository publishes cannot be reproduced without one. That arm was deleted
# along with the hosted backend, and the deletion quietly made a published
# result unreproducible; restoring it in the tool rather than in the library is
# how both things stay true at once.
#
# So the scope is checked too, below: if a network client ever appears in the
# library or the app, this still fails.
note "No network client, no credential store, no vendor endpoint"
if grep -rnE 'URLSession|api\.anthropic|cdn\.jsdelivr|img\.youtube|x-api-key|ANTHROPIC_API_KEY|SecItemAdd' \
     --include='*.swift' solvr.ai Packages/SolvrCore/Sources/SolvrCore \
   | grep -v 'LegacyCredentialPurge.swift' \
   | grep -v '^\S*: *//' ; then
  echo "the app reaches the network or stores a credential" >&2
  fail=1
else
  echo "none in the app or in the library it links"
fi

# The inverse of that scope, asserted rather than assumed: the HTTP client is
# allowed in exactly one directory, and that directory is not in the app.
note "The network client lives only in the measurement tool"
strays=$(grep -rnE 'URLSession' --include='*.swift' Packages/SolvrCore/Sources \
         | grep -v '^\S*: *//' \
         | grep -v '^Packages/SolvrCore/Sources/solvr-eval/' || true)
if [ -n "$strays" ]; then
  echo "a network client escaped into the shipped library:" >&2
  echo "$strays" >&2
  fail=1
elif grep -q 'name: "SolvrCore".*solvr-eval' Packages/SolvrCore/Package.swift; then
  echo "the library depends on the measurement tool" >&2
  fail=1
else
  echo "only under Sources/solvr-eval/, which the app does not link"
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
