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

## A label is not a question, and `String` cannot tell you which one it is

The hardest bug in this repository to date presented as a model that had gone
mad. A photograph of `∫ 3x² + 2x + 4 dx` produced a lesson titled *Understanding
Scanning*, a topic line reading `SCANNING`, and five suggested videos called
"Scanning", from Khan Academy and 3Blue1Brown. Nothing was wrong with the model.
It was asked about the word.

The app had four strings in play for one photographed solve:

| string | where | what it was |
|---|---|---|
| `"Scanning..."` | `ContentView` | what the header said while the camera closed |
| `"[Scanned Image]"` | the results view model | a sentinel other views compared against |
| a model-written title | a detached task, seconds later | a *label* for the history list |
| the text Vision read | inside a provider, per request | **the only one that was a question** |

Every one of them was a `String`, so every one of them fitted wherever a problem
was expected. Three of the four reached a prompt.

The route was history. `Problem` had one text field, it held whichever label was
current when the student backed out, and re-opening the entry set the solve's
input to it -- so any tab that had not been generated the first time was
generated from the label. The store on the phone this was found on has **six of
nine rows carrying a label where the question should be**: one `"Scanning..."`,
three `"Scanned Problem"` (the fallback when recognition failed), and two
model-written titles. The last of those is the worst kind, because a lesson about
"Augmented Matrix Vector Solution" is *plausible*, and nobody would photograph it
and file a bug.

Sanitising the strings would have been the obvious fix and the wrong one. What
the code needed was for a label not to be the same *type* as a question:

```swift
struct Solve {
    let id: UUID
    let question: String     // the only string a prompt is ever built from
    let source: Source       // .typed | .photograph(jpeg: Data)
}
```

There is one initialiser, `SolveBuilder` is the only thing that calls it, and
every prompt-taking API takes the question off it. `ProblemInput` is gone, so is
`SightedProvider`, and so is image input on the provider protocol: after the
builder there is no unresolved input left in the system. A display string now has
no path into a prompt that type-checks.

Two things fell out that were not the point and are worth more than they cost.
Recognition moved *above* the four surfaces instead of below them, so a
photograph is read once instead of five times -- the memo meant to prevent that
had never once hit, because the app built a new wrapper per request. And a
photograph nothing can be read from now fails on the camera screen, once, where
taking another picture is the fix, rather than four times on a results screen the
student has already been pushed to.

## The converter is checked now, not reviewed

`MathNotation` rewrites the notation Apple's on-device model writes -- it returns
correct maths in the wrong form, `∫[0,1] 3x^2 dx`, and no amount of prompt
wording changes that. It has also produced three separate corruption bugs:
`\sqrt16` (the radical losing its argument), `\sine` (a function-name rule
firing inside a word), and `\intx` (a control word with nothing terminating it).
All three shipped. All three were found by a person looking at red text on a
phone.

The third one is instructive, because it was thirty bugs rather than one. The
symbol table substituted Unicode operators for LaTeX commands with
`replacingOccurrences`, and a LaTeX control word runs to the first non-letter --
so `πr²` became `\pir^{2}`, `2πn` became `2\pin`, `Σx_i` became `\Sigmax_{i}`,
and every entry in the table had the same fault. The quietest of them *rendered*:
`∈f(x)` became `\inf(x)`, and `\inf` is a real command, the infimum, so the
wrong symbol was drawn with nothing red to notice.

And here is the part that decided the fix. **KaTeX renders every one of those
Unicode characters as it stands.** `∫ x^{n} dx`, `πr^{2}`, `∑_{n=1}^{5} n`, `θ`,
`∞`, `⋅`, `→`, `Δx`, `∂f/∂x` all parse under `throwOnError: true`. The converter
was taking strings that rendered and producing strings that did not.

A converter whose job is to improve something that already works has to be
*checked*, and the thing that can check it is the renderer. So KaTeX is now the
arbiter, in three places:

- **`swift test`.** `KaTeXOracle` loads the app's own `katex.min.js` into a
  `JSContext` -- `renderToString` needs no DOM -- and asserts two properties: that
  every symbol in the table survives a letter after it, and that **no conversion
  breaks a string that already rendered**, over the maths the model actually wrote
  in the published records. Eight milliseconds to load the bundle, half a
  millisecond a string. The second property found two live regressions in strings
  from a shipped run.
- **The page.** Display maths travels in a `data-tex` attribute on an empty
  element and is typeset explicitly with `throwOnError: true`. When it throws, the
  element becomes the source string in monospace with "could not be typeset --
  shown as written" beneath it. Red text was the wrong failure mode: it reads as
  *the maths* being wrong rather than *the rendering* having failed, and a student
  cannot tell those apart.
- **The harness.** Records carry each maths field twice, before and after
  conversion, index-aligned, so `converterRegressions` is a column: how many
  strings KaTeX accepted before we touched them and rejected after. All three
  historical bugs would have appeared in it on the run that introduced them.

The boundary bug is fixed too -- one scan, and a space after a command when a
letter follows -- but that is no longer the thing standing between a student and
red text.

## OCR runs before the network, and that is the point

`OCRService` uses Vision's `VNRecognizeTextRequest` on device. The order matters
for two reasons beyond speed:

- **What leaves the device is text, not a photograph**, whenever OCR succeeds.
  A photo of a worksheet may contain a name, a school header or another student's
  work in frame; the extracted expression does not.
- **An image costs far more tokens than the sentence it contains.** Sending
  `∫₀¹ 3x² dx` instead of a 4-megapixel photograph is the difference between a
  cheap request and an expensive one.

Finding *which* problems are on a page used to be the harder case, and it used to
be a hosted vision call: `detectProblems` sent the photograph to a model that
could see it and asked for bounding boxes back. That backend is gone and Apple's
on-device model cannot replace it — it accepts no image input at all.

Vision does it now. The trade is real in both directions. A vision model could
answer "which of these lines form one problem", which is a semantic question, and
Vision cannot: it returns one box per recognised line and the grouping is not
attempted. What Vision gives back is a *measured* box rather than coordinates a
model was asked to estimate, which is the part that used to drift. The crop
overlay still exists because OCR on a full page of homework returns everything at
once.

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

## The camera path, finally measured

Every published number in this repository came from typed text. The model is the
same on both paths; what reaches it is not, and nothing recorded what Vision made
of a photograph or checked it against anything. That is how a picture of an
integral produced a lesson about flatbed scanners with every table still green.

There are two arms now, because a Mac is not a phone and this repository has
already been caught believing one about the other.

`solvr-eval --set camera` reads photographs with their contents written down
beside them, once each, through the same `SolveBuilder` the app uses, and then
asks the graded surfaces about what came out. Recognition gets its own record:
"the photo was misread" and "the model was wrong" are different failures with
different fixes, and a run that averages over them is measuring neither.

`-SolvrCameraSelfTest YES` does the same on the phone and one thing more. It
builds the real page for each surface with the real `HTMLBuilder`, loads it into a
real `WKWebView` with the vendored KaTeX, and reports how many strings the page
could not typeset. A Node check can tell you a string parses; only that can tell
you the page drew it. Fixtures are pushed into the app's container rather than
bundled, so a Release build measures Release code with no test data compiled into
it.

The first fixture already says something the typed arm never could. Vision --
both on a Mac and on the phone -- reads the handwritten integral sign as a bullet
and drops the exponent, so `∫ 3x² + 2x + 4 dx` reaches the model as
`• 3x + 2x + 4 dx`. The model then answers *that* problem, carefully, and gets it
right for the question it was given. All four surfaces were asked the same thing
and every display string typeset. **On this path the dominant failure is
recognition, and it was invisible.**

Which is why the app now shows the recognised text under the photograph. It is
the only thing a student can check, and it is byte-for-byte what every tab was
asked about.

## What is not solved

- **Handwriting.** Vision reads printed problems well and handwriting unevenly,
  and the measured case above is not a near miss -- an integral sign became a
  bullet. Showing the student what was read is a mitigation, not a fix.
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
