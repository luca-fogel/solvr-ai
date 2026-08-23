# Engineering notes

The long version: what it takes to get typed, renderable maths out of a language
model, and which of the obvious approaches quietly produce wrong output.

Most sections correspond to tests in `Packages/SolvrCore/Tests/SolvrCoreTests`.
Where something is a measurement it says so; where it is a judgement call it says
that instead.

For what the app is and how to run it, see the [README](../README.md).

---

## The prompts ask for strict JSON, and mostly get it

Every request asks for a specific JSON shape, matched to a `Codable` type in
`SolvrCore/Models/`. The prompts live with the provider that sends them -- now only
`Providers/OnDeviceProvider.swift`, which carries its own -- because a prompt is
a property of the backend, not of the app. That principle is what made deleting
the hosted backend a deletion rather than an untangling: its prompts went with
it. The lesson prompt is the most demanding: a title, a topic line, an
introduction, an array of sections each with an optional formula, an optional
note and an optional list of steps, and a closing takeaway.

Two things about that are worth stating, because they are what the rest of this
document is about.

**Asking for JSON is not the same as receiving it.** The failures are not random:
they are markdown fences, prose wrapped around the object, LaTeX backslashes that
JSON rejects, and truncation when a response hits the token limit. Each has a
different fix, and they have to be applied in a specific order.

**The prompt asks the model to teach the concept rather than solve the given
problem.** `fetchLesson` says so explicitly, because a lesson that solves the
exact question in front of the student is just the Steps tab again. That
distinction is a pedagogical decision encoded in a prompt, and it was the single
biggest improvement to the app's usefulness.

## Valid JSON can still be the wrong answer

This is the finding that reorganised the whole decode path.

`"\frac{d}{dx}"` **is valid JSON.** `\f` is the escape for a form feed, so the
document parses, and the decoded string is:

```
"\u{0C}rac{d}{dx}"
```

A form feed followed by `rac{d}{dx}`. No error is raised, no exception is thrown,
nothing in the app can tell that anything went wrong — the user just sees maths
with a missing command and a stray character. Every fraction, every `\forall`,
every `\text`, silently damaged.

The consequence is that the intuitive ladder — try a strict parse, and repair
only if it fails — **cannot work**, because the strict parse succeeds. Repair has
to run *before* the first decode attempt, unconditionally. `LLMJSON.decode` does
that, and `validJSONCanStillBeWrong` asserts the corrupted reading directly, so
the ordering cannot be "tidied" back later by someone who assumes strict-first is
obviously correct.

The general form of the lesson: **a response that parses is not the same as a
response that parsed correctly.**

## A repair may never damage input that was already valid

The previous implementation doubled every single backslash it found, protecting
already-doubled ones with a placeholder first. It fixed `\frac`. It also turned
this:

```json
{"title": "the \"chain rule\" explained"}
```

into a literal backslash followed by an unescaped quote — breaking a document
that had arrived perfectly well formed. A repair layer that damages correct input
is worse than no repair layer, because the failure lands on the cases that were
already working.

`LLMJSON.repairLaTeXEscapes` walks the text tracking string boundaries and
decides per backslash:

| what follows the backslash | decision | why |
|---|---|---|
| `"` `\` `/` | keep | unambiguously valid JSON escapes |
| `u` + four hex digits | keep | a real unicode escape |
| a letter that is **not** `b` `f` `n` `r` `t` | double | `\alpha`, `\int`, `\sqrt` cannot be escapes |
| `b` `f` `n` `r` `t` | look at the whole word | `\frac` is LaTeX; `\nNext line` is a newline |
| anything else (`{`, `(`, `\|`, space, digit) | double | not a legal escape, so it came from LaTeX |

The ambiguous case is decided by a list of known LaTeX commands whose first
letter collides with a JSON escape letter — `frac`, `times`, `theta`, `nu`,
`beta`, `text` and about twenty more, matched by prefix so `textbf` is caught by
`text`.

**The honest limitation:** a LaTeX command starting with b/f/n/r/t that is not on
that list will be read as an escape. That fails loudly at decode time instead of
silently corrupting text, which is the trade being chosen. And in the other
direction, a string that legitimately contains a tab followed by `imes` will be
read as `\times` — accepted, because in a maths app the second reading is right
far more often.

The property that matters is tested directly: `idempotent` asserts that running
the repair twice changes nothing further, and four separate tests assert that
valid escapes, newlines, unicode escapes and already-doubled backslashes come out
untouched.

## The rest of the ladder

In order, cheapest first, after the repair:

1. **Slice out the JSON.** Models wrap objects in prose — "Sure! Here you go:" —
   so `sliceJSONBody` takes the span from the first `{` to the **last** `}`.
   Outermost rather than first-balanced, because nested objects are the norm here
   and the first `}` is almost never the end of the document.
2. **Decode the repaired text.**
3. **Decode the original text.** If the repair itself broke something, the input
   still deserves a try before giving up.
4. **Round-trip through `JSONSerialization`.** It accepts some escaping that
   `JSONDecoder` rejects, so re-serialising normalises the document.
5. **Give up and return `nil`**, so the caller can fall back to showing the
   model's prose rather than presenting a half-filled object as a solution.

Each rung reports itself as a `Provenance` — `.strict`, `.repaired` or
`.normalised` — where `.strict` means the repair changed nothing at all. That
distinction is worth carrying: a value that needed rescuing is evidence about the
prompt, and the app logs it for exactly that reason. It *was* the instrument for
comparing a self-hosted model against its fine-tune, where schema compliance was
the interesting axis — and that comparison is the one published result this
repository has. It is unreachable from the shipping app: guided generation never
produces a string to repair. The ladder still runs, on the demo fixtures.

Two failure modes return `nil` deliberately rather than something plausible: a
response truncated by the token limit, and JSON of the wrong shape. A partially
decoded solution is worse than no solution, because the user cannot tell which
half is missing.

## Five requests at once, and four slots

The results screen fires Steps, Lesson, Formulas, Videos and a title
simultaneously, because the first tab should be populated before the user has
finished reading the problem. The API rate-limits well before the device runs out
of sockets, so `RequestQueue` holds the concurrency at four, and a 429 is retried
once after the `retry-after` interval.

The bug worth recording: the queue was acquired once and released at **five
separate call sites** — success, rate-limited retry success, retry failure, other
`ClaudeError`, and any other error. A slot missed at any one of them is gone for
the life of the process, and after four misses the app stops making requests
entirely, with nothing on screen to say why. It is now a single `withSlot` with
`defer`, and `slotReturnedOnThrow` and `failuresDoNotStarveTheQueue` assert the
slot comes back.

The retry also stopped swallowing cancellation. `try? await Task.sleep` meant a
user who navigated away still paid for the retry; it is `try await` now, so
leaving the screen stops the work.

## OCR runs before the network, and that is the point

`OCRService` uses Vision's `VNRecognizeTextRequest` on device. The order matters
for two reasons beyond speed:

- **What leaves the device is text, not a photograph**, whenever OCR succeeds.
  A photo of a worksheet may contain a name, a school header or another student's
  work in frame; the extracted expression does not.
- **An image costs far more tokens than the sentence it contains.** Sending
  `∫₀¹ 3x² dx` instead of a 4-megapixel photograph is the difference between a
  cheap request and an expensive one.

Claude Vision is still used for the harder case — `detectProblems` finds and
boxes multiple problems on a page, which Vision's text recogniser cannot do,
since "which of these lines form one problem" is a semantic question. The crop
overlay exists because OCR on a full page of homework returns everything at once.

## Maths rendering

`Utilities/HTMLBuilder.swift` builds an HTML document per results tab and renders
it in a `WKWebView` with KaTeX. Two decisions:

**Model output is escaped, LaTeX is not.** The prose around an expression is
escaped through `LLMJSON.escapeHTML` — model output routinely contains `<`, `&`
and quotes, and `if x < 0` should not open a tag — while the maths inside `\[ \]`
is handed to KaTeX intact, because escaping it would defeat the point. There is
exactly one HTML-escaping implementation, in `SolvrCore`, with tests; a second
copy in the app had already drifted into forgetting quotes.

**Dollar delimiters are stripped before wrapping.** Models emit `$...$`, `$$...$$`
and bare expressions interchangeably, and a `$` that survives into the KaTeX
input renders as a literal dollar sign in the middle of an equation.

## Model selection, and a migration shim

`selectedModel` maps stored identifiers forward: a preference saved as
`claude-sonnet-4-20250514` resolves to the current Sonnet, and the retired Haiku
identifier resolves to the current Haiku. Model identifiers are retired faster
than users open Settings, and the alternative is an app that starts returning 404
after an upgrade for a reason the user cannot see or fix.

## Demo mode

`-SolvrDemo YES -SolvrScreen <name>` opens one screen, populated, with no key and
no network. It exists for three reasons: an app that needs a credential before it
shows anything cannot be evaluated by anyone; screenshots have to be
reproducible; and the fixtures are a worked example of what the prompts are
asking for.

Deliberately not a shortcut around the real code: the fixtures are raw JSON with
unescaped LaTeX in them, decoded through the production ladder, so demo mode
exercises the repair on every launch. The worksheet on the scanner screen is
*drawn* at runtime by `DemoPage` rather than bundled as a photograph — a
simulator has no camera, and a photograph of real homework would be someone's
work.

Screenshots are scripted rather than taken by hand. An earlier attempt drove the
UI by synthesising taps at pixel coordinates measured from a screenshot; it
worked, and it was unreproducible by anyone else and broke the moment a layout
moved. A launch argument is not clever, and it regenerates every image in the
README with one command.

## What is not solved

- **No verification of the maths.** The app renders what the model says. A wrong
  step is displayed with the same confidence as a right one, and detecting that
  automatically is a genuinely hard problem, not an oversight.
- **Handwriting.** Vision reads printed problems well and handwriting unevenly.
- **The constrained-versus-unconstrained comparison, on the hosted path — and
  now it never will be.** Three backends were built behind one protocol: the
  hosted API, a local OpenAI-compatible server, and Apple's on-device
  `FoundationModels`. The last settles the question this document raises, in the
  direction the document expected: `@Generable` constrains decoding to a schema,
  so the repair ladder is *structurally unnecessary* on that path. The same
  comparison on the hosted API was wired (`usesStructuredOutputs`) and never
  made a single call — and that backend has since been removed, so the gap is
  now permanent rather than pending. Only the local backends were ever measured
  against each other ([evaluation-local.md](evaluation-local.md)).
- **Grouping OCR lines into multi-line problems.** The scanner detects one
  recognised line at a time. Deciding which lines belong to the same problem is
  the obvious next step and is deliberately not attempted, because guessing it
  is how the previous, model-estimated boxes ended up spanning half a page.
- **Streaming.** Responses arrive whole, so a long lesson shows a shimmer rather
  than filling in progressively.
