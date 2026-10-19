# Contributing

The app is a personal project, but the parts that are generally useful — the
model-output handling in `Packages/SolvrCore` — are the parts most likely to have
a bug you have hit too. Those are the contributions I most want.

## Start here

```sh
swift test --package-path Packages/SolvrCore    # ~2s, no Xcode, no simulator, no key
open solvr.ai.xcodeproj                          # then Settings -> Demo mode
```

Demo mode means you can run and change the whole results surface without an API
key. Please keep it working; it is what makes this repo reviewable by a stranger.

## The rules this code lives by

- **A repair may never damage input that was already valid.** If you touch
  `LLMJSON`, the tests asserting that valid escapes, newlines and unicode escapes
  survive untouched are not negotiable.
- **A response that parses is not a response that parsed correctly.** See
  `validJSONCanStillBeWrong` in the tests and the note it points to. Do not
  reorder the decode ladder to try strict parsing first, however obviously
  correct that looks.
- **`nil` beats a plausible half-answer.** Truncated or wrongly shaped responses
  return nothing, so the caller can fall back to showing the model's own words.
- **Nothing leaves the device.** No `URLSession` / credential store in
  `solvr.ai` or `Packages/SolvrCore/Sources/SolvrCore` — `tools/check.sh` enforces
  this. HTTP belongs only under `Sources/solvr-eval/` for measurement.
- **Fixtures and examples are synthetic.** No real student work, no names, no
  tutoring records, in any file, ever.

## Tests

Anything that is pure text handling belongs in `Packages/SolvrCore` with a test,
not in the app. The rule of thumb: if it can be tested without a simulator, it
should live where it can be.

If you found a case where a model returned something misleading, add the test
that fails on the naive reading first, then the fix.

## Regenerating the images

```sh
./tools/screenshots.sh          # every screenshot in docs/images, from a simulator
./tools/screenshot-mac.sh       # the Mac Catalyst build
swift tools/render-mockups.swift  # the hero, social card and feature cards
```

## Sign your work (DCO)

Add a `Signed-off-by` line to each commit — `git commit -s` does it for you:

```
Signed-off-by: Your Name <your.email@example.com>
```

That line is the [Developer Certificate of Origin](https://developercertificate.org/):
you are stating that you wrote the patch, or otherwise have the right to submit it
under this project's licence (GPL-3.0). It is one line, not a copyright
assignment — you keep the copyright in your own work.
