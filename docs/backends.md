# One interface, one model — and why the interface stayed

> **This document is partly history now.** Solvr shipped three backends behind
> one `SolutionProvider`: a hosted Anthropic API, a self-hosted
> OpenAI-compatible server, and Apple's on-device model. **The first two were
> removed** — they were the only reason the app held a credential or opened a
> socket, and the measurement work they existed for is finished and published in
> [evaluation.md](evaluation.md) and [eval-records/](eval-records/).
>
> What is written below about the protocol, the OCR bridge and the concurrency
> limits is current. What is written about the hosted and self-hosted providers
> describes code that is no longer in the tree; it is kept because the design
> reasoning is what makes the remaining shape legible, and because deleting the
> account of a thing you removed is how a repository starts lying about how it
> got here. `git log` has the code.

Solvr used to have exactly one way to get an answer, and the type system said so.
`ClaudeAPIManager` was a singleton holding the prompts, the request queue, the
decode ladder, the app's loading flags, and a demo short-circuit at the top of
all twelve of its methods. Four SwiftUI views named it in their type signatures,
because the error enum was nested inside it.

It now has one way to get an answer again — but behind a protocol, which is not
the same thing, and the difference is the point of this document.

## Why keep a seam with one implementation behind it

Three reasons, none of them "we might add a backend later":

1. **The evaluation harness drives the same code the app drives.** That is only
   true because `solvr-eval` depends on the protocol rather than on the app. A
   harness with its own client measures a second implementation and reports the
   numbers as if they came from the first.
2. **Demo mode is a provider.** `FixtureSolutionProvider` is how every screen is
   driven with no model at all, and it is what makes the app usable on hardware
   without Apple Intelligence. Collapsing the seam would put a demo branch back
   inside the real path, which is exactly the shape `ClaudeAPIManager` had.
3. **`SightedProvider` is a decorator.** Apple's model accepts no image input, so
   something has to bridge OCR in — and it does it by inspecting
   `acceptsImageInput` rather than by knowing which backend it wrapped.

## The protocol

`SolutionProvider` (in `SolvrCore`) is the whole seam:

```swift
public protocol SolutionProvider: Sendable {
    var identifier: String { get }
    var maxConcurrentRequests: Int { get }
    var isConfigured: Bool { get }
    var acceptsImageInput: Bool { get }

    func lesson(for problem: ProblemInput) async throws -> LessonContent
    func steps(for problem: ProblemInput) async throws -> [StepItem]
    func formulas(for problem: ProblemInput) async throws -> [FormulaItem]
    func videos(for problem: ProblemInput) async throws -> [VideoItem]
    func chatReply(to message: String, about problem: String,
                   history: [ChatMessage]) async throws -> String
    func title(for problem: ProblemInput) async -> String
}
```

`ProblemInput` is `.text(String)` or `.image(Data)`. That one type collapsed
twelve methods into six: there were four fetchers for typed problems and four
near-identical ones for photographs, and the only difference was which API call
they made.

Three things are on the protocol that might look like they belong elsewhere, and
each is there because it genuinely differs per backend.

**Prompts.** They live with the provider, not in the app. A 4B needs shorter,
more constrained instructions than Opus, and a backend whose decoding is already
constrained needs no schema in its prompt at all.

**Concurrency.** `maxConcurrentRequests` is 4 for a hosted API, and must be 1 for
Apple's on-device model, which throws `GenerationError.concurrentRequests` if
asked two things at once. Solvr fans out four requests per solve, so this is not
a detail.

**Whether it can see.** See below.

## Why it lives in SolvrCore

Two reasons, both load-bearing.

The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a protocol
declared there would be implicitly main-actor isolated and every conformance
would inherit that. In the package it is non-isolated.

And the evaluation harness has to measure *the code the app actually runs*. A
harness with its own HTTP client would be measuring a second implementation while
reporting the numbers as if they came from the first. So `AnthropicProvider` is in
`SolvrCore` too, with the key, the network check and the image passed in rather
than reached for — which is also why nothing in it needs UIKit, and why
`swift run solvr-eval` works with no Xcode.

That forced the models across as well. `LessonContent`, `StepItem`,
`FormulaItem`, `VideoItem` and `ChatMessage` are Foundation-only `Codable`
structs, and they belong beside the ladder that decodes them.

`SolvrCore` stays Foundation-only. The moment it imports UIKit it stops being
runnable by `swift test`, and the tests are most of the reason it exists.

## Reading a photograph

Solvr reads photographed problems. Whether the *model* does is a different
question, and the answer is often no.

Checked against the iOS 26.5 SDK rather than assumed: **`FoundationModels` has no
image input at all.** `PromptRepresentable` is conformed to by `String`, `Prompt`,
`Array` and `Optional`, and there is no image, attachment or pixel type anywhere
in the framework's 1501-line interface. Apple's on-device model cannot see. A
locally served text model is in the same position.

So a provider declares `acceptsImageInput`, and `SightedProvider` wraps the ones
that answer `false`: it recognises the text in the photograph first, keyed so one
image is read once rather than once per surface. The recogniser is injected rather
than imported, which keeps the bridge in `SolvrCore` under test without dragging
Vision in with it. `ProviderFactory` decides to wrap by *asking the provider*, not
from a list kept beside it, so a backend added later cannot forget to declare
itself and silently lose the camera.

This is a downgrade and it is labelled as one — a wrapped provider reports
`identifier` as `<backend>+ocr`. Native vision reads a fraction as a fraction;
text recognition reads it as two numbers with a line between them, and
superscripts, integral signs and matrices fare worse. A wrapped backend is
answering a harder question than one that sees the image, which is why the
capability is recorded per backend instead of assumed.

Worth noting: `OCRService` already existed in the repo and had never been called
from anywhere. Solvr has always relied entirely on hosted vision for images.

## Demo mode is a backend

It always was — hand-inlined as fourteen short-circuit blocks. It is now
`FixtureSolutionProvider`, the second conformance, which is what shows the
protocol is a real seam rather than a rename. Two properties are preserved
deliberately:

- The fixtures are raw JSON **text** carrying unescaped LaTeX, decoded through
  the production ladder. Demo mode therefore exercises the repair layer on every
  launch instead of bypassing it, which makes `tools/screenshots.sh` a regression
  test on the parser. A provider returning typed values directly — guided
  generation — would quietly stop testing it.
- Demo mode resolves **before** any key check, which is why it needs no
  credential, and the provider is resolved **per request**, so the Settings
  toggle takes effect without a relaunch.

It lives in `SolvrCore` so the harness can exercise the whole pipeline —
compliance, grading, reporting — with no key and no spend. A harness that can
only be run by paying for it does not get run.

## Where the repair ladder actually earns its keep

The comfortable story is that a hosted model needs the JSON repair layer and a
guided on-device model cannot. The first half is wrong.

Schema compliance is not a property of model quality. It is a property of the
**decoding mechanism**:

| backend | decoding | repair ladder |
| --- | --- | --- |
| Anthropic, as Solvr calls it today | unconstrained prose JSON | **load-bearing** |
| Anthropic + `output_config.format` | constrained server-side | unreachable |
| Apple on-device `@Generable` | constrained on-device | impossible to need |
| Local Mac via `mlx_lm.server` | **unconstrained** | **load-bearing** |

That last row was checked, not assumed: `mlx_lm.server` 0.31.3 accepts no
`response_format`, `json_schema`, grammar or guided-decoding option, and its only
logits processors are repetition penalty and logit bias. **The self-hosted
backend is the one that genuinely cannot be constrained.** Far from being a
hosted-API tax, the repair ladder is what makes self-hosting viable.

One correction to the guided-generation half, too. `GenerationError` includes
`decodingFailure`, alongside `exceededContextWindowSize`, `guardrailViolation` and
`refusal` — so generation can still fail. What is genuinely impossible on that
path is *string-level corruption*: you are handed a typed value, never a `String`,
so there is no `\frac`-versus-form-feed ambiguity to get wrong. Guided generation
does not remove failure. It removes **silent** failure.

See [evaluation.md](evaluation.md) for how that gets measured.

## What the on-device backend actually does, measured

Run on 2026-08-22 via the launch-argument self test
(`-SolvrSelfTest YES`, report written to the app container). Apple's model is not
present on this Mac, but the iOS 26.5 simulator reports `.available`, so the path
is verifiable without a device.

| surface | result | time |
| --- | --- | --- |
| steps | 4–5 steps, final answer **correct** | 7.6 s |
| lesson | 3 sections | 6.0 s |
| formulas | 3 formulas | 3.2 s |

No string was parsed at any point, so no rung of the repair ladder was
reachable. That is the central claim of the project, now an observation.

Roughly 17 s for all three, because they serialise. Against the hosted API the
same three run concurrently. That is the honest cost of not sending anything
anywhere.

### The interesting failure: right maths, wrong notation

Asked for `\int_{0}^{1} 3x^{2}\,dx`, it returned:

```
∫[0,1] 3x^2 dx
```

Correct mathematics. Notation that renders as literal text. And the important
part: **tightening the instructions did not fix it.** Naming the commands, giving
worked examples, and saying "never plain text" in both the `@Guide` descriptions
and the session instructions changed the *flavour* of the wrong answer, not its
correctness.

So on this surface the on-device model's weakness is presentation rather than
mathematics, and prompt wording is not a strong enough lever to move it. That is
a concrete argument for a fine-tune rather than a hypothetical one — it is exactly
"a small model that reliably produces *my* output shape".

`MathNotation` closes the part of the gap a deterministic string pass can close:
Unicode operators to commands, bracketed integral limits to sub/superscripts,
bare exponents braced, function names to commands. It inherits `LLMJSON`'s rule
that a conversion may never damage input that was already correct — anything
containing a backslash command is returned untouched — it is idempotent, and its
tests use the strings the model actually emitted rather than invented ones. After
it, steps render as real typeset maths.

What it does **not** fix, and should not try to: the formulas surface writes the
*word* "integral" rather than the symbol (`integral of x^{n} dx = x^{n+1}/(n+1) + C`).
Rewriting English into notation is not something a string pass should attempt.
Left visible, because it is the measurement that justifies the next phase.

A second, smaller finding: the lesson title came back as the student's problem
restated. Guided generation fills fields in declaration order, so `title` is now
declared *last*, after the sections it is supposed to name. That moved it from
"Evaluate the definite integral of 3x^2 from 0 to 1" to "Evaluating the Definite
Integral of 3x^2 from 0 to 1", with `topic` becoming "Definite Integrals".
Better; not fixed.

## Constraints that will shape the next backend

Recorded here because they were verified against the SDK and are easy to
rediscover the expensive way.

- **`SystemLanguageModel.contextSize` is 4096.** Prompt plus completion. The
  current lesson prompt spends roughly 400 tokens restating a JSON schema and
  then asks for three to five sections of LaTeX; it will not fit as written.
  `includeSchemaInPrompt: false` is the cheap fix — constrained decoding already
  enforces the shape, so the schema in the prompt is pure cost.
- **One request at a time**, per `GenerationError.concurrentRequests`.
- **Availability is a runtime question**: `deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`. The oldest device that gets an
  on-device model at all is the iPhone 15 Pro.
- **`GenerationOptions` supports `.greedy` and seeded sampling**, so the on-device
  arm of the evaluation can be made reproducible.
- **`RequestQueue.withSlot` has no timeout.** Against a hosted API that is fine.
  Against a Mac that may be asleep, four slots park forever and the UI explains
  nothing.
