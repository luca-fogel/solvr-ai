# Camera fixtures

Photographs with their contents written down, so the camera path can be measured
instead of assumed.

Every published number in this repository used to come from typed text. That is
the easier half: the model is the same, but what reaches it on the camera path is
whatever Vision made of a photograph, and nothing recorded that or checked it. A
photograph of `∫ 3x² + 2x + 4 dx` produced a lesson about flatbed scanners and
every table stayed green.

## What a fixture is

An image, and an entry in `manifest.json`:

| field | meaning |
|---|---|
| `id` | stable, so two runs can be diffed by fixture |
| `file` | the image, beside the manifest |
| `expectedText` | what a **correct reading** produces — not what the model should answer |
| `answer` | the right answer, in sympy's syntax, for `grade_answers.py` |
| `numeric` | present only when the answer is a single real number |
| `expectUnreadable` | `true` for the fixture that must be **refused** |
| `notes` | what this picture is for |

Two of those are worth stating plainly.

**`expectedText` separates reading from solving.** They are different failures
with different fixes, and a run that averages over them is measuring neither. The
first fixture here is the case in point: Vision reads the handwritten integral
sign as a bullet, so the model is asked a nonsense question and answers it
carefully. Nothing about that is a fault of the model.

**`expectUnreadable` is not a curiosity.** A photograph with nothing legible in
it has to produce one honest sentence, on the camera screen, before a results
screen exists. Only measuring the pictures that work would let that quietly stop
being true.

## Running it

```sh
# On this Mac. Vision here is not Vision on a phone; this measures the pipeline.
swift run --package-path Packages/SolvrCore solvr-eval \
  --backend on-device --set camera --images docs/fixtures/camera \
  --out eval-camera.jsonl
tools/eval/grade.sh eval-camera.jsonl

# On the phone, which is the only authority on the phone. Fixtures are pushed
# into the container, so none of this is in the binary.
xcrun devicectl device copy to --device <udid> \
  --domain-type appDataContainer --domain-identifier Lulu.solvr-ai \
  --source docs/fixtures/camera --destination Documents/fixtures
xcrun devicectl device process launch --console --device <udid> \
  Lulu.solvr-ai -- -SolvrCameraSelfTest YES
xcrun devicectl device copy from --device <udid> \
  --domain-type appDataContainer --domain-identifier Lulu.solvr-ai \
  --source Documents/camera-selftest.log --destination .
```

## The set this wants

One fixture is here. The rest are pictures that have to be taken, and they are
chosen to cover the ways this path fails rather than the ways it works:

1. **the whiteboard integral** — handwriting, at an angle. *(present)*
2. **a printed quadratic**, `x² − 5x + 6 = 0` — the easy case, and the control.
3. **a printed fraction**, `(x+1)/(x−2) = 3` — the case the notes call out: text
   recognition reads a fraction as two numbers with a line between them.
4. **a handwritten radical**, `√(x² + y²)` — the character that has already
   caused two rendering bugs.
5. **handwritten `2sin(θ) − 1 = 0`** — Greek, and the problem that is answered
   correctly on a Mac and wrongly on an iPhone.
6. **a page with several problems on it** — the crop overlay exists because OCR
   on a full page returns everything at once.
7. **a deliberately unreadable frame** — blurred, or with no text at all. This is
   the one that must be refused.

Nothing personal in frame, and nothing anybody else wrote: these are published.
