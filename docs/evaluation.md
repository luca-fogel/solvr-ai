# Measuring Solvr's backends

> **Read this first.** Solvr now runs on Apple's on-device model and nothing
> else. The hosted and self-hosted backends described below **have been removed
> from the app.** Everything in this document still stands as an account of what
> was measured and how — and the 387 records in [eval-records/](eval-records/)
> are unchanged, still regenerate the tables byte-for-byte, and are still
> checked by `tools/check.sh`. A measurement does not stop being true because
> the code that produced it was deleted. It does stop being repeatable, and that
> is stated where it matters below.

Solvr could be pointed at more than one model. This describes how the comparison
was measured, what the numbers mean, and what they do not show.

Nothing here is an opinion about which backend is better. The point of building a
harness was to stop having that conversation in adjectives.

## The instrument, and why it had to be fixed first

`LLMJSON.decode` turns a model's answer into a typed value, cleaning up on the
way: a markdown fence is removed, prose either side of the JSON is trimmed, LaTeX
backslashes that JSON rejects are escaped, and as a last resort the document is
renormalised through `JSONSerialization`. `Decoded.provenance` reported which of
those had happened, and it was the obvious instrument for schema compliance.

It was the wrong instrument, in a way that mattered:

```swift
let cleaned = stripCodeFences(raw)
let repaired = repairLaTeXEscapes(cleaned)
let provenance: Provenance = repaired == cleaned ? .strict : .repaired
```

`provenance` compared the repaired string against the **post-fence-strip** one,
so fencing was invisible — a response wrapped in ```` ```json ```` and otherwise
perfect reported `.strict`. And prose slicing happened at the *call sites*,
before `decode` was entered at all, so that was invisible too.

Both blind spots run in the flattering direction, and both cover exactly what a
small local model does most. A 4B that fenced every single response would have
scored an identical compliance rate to a frontier model emitting bare JSON. The
headline finding of a backend comparison built on that instrument would have been
wrong, and wrong in the direction that looks good.

So each step now reports itself, in `LLMJSON.Compliance`:

| field | what it means |
| --- | --- |
| `wasFenced` | the response contained a markdown code fence |
| `wasSliced` | prose around the JSON had to be trimmed away |
| `escapesRepaired` | LaTeX backslashes had to be escaped before JSON accepted them |
| `wasNormalised` | `JSONDecoder` refused it; it parsed only after a round trip |
| `usedPlainTextFallback` | no JSON was recovered and the prose was wrapped to fill the shape |
| `isClean` | none of the above — **this is the number to compare** |

Slicing moved inside `decode`, so nothing happens to a response outside the
instrument's view. `provenance` survives as a summary of the record, so it still
reads well in a log line. Seven tests in `ComplianceInstrument` hold the two
blind spots shut.

## What is measured

**Schema compliance** — the fraction of responses that decoded with nothing done
to them, reported **per surface**. Per surface matters: the `videos` prompt asks
for no LaTeX at all and scores a free 100%, so a single cross-surface average
flatters whichever backend is worst at the hard surfaces.

**Maths correctness** — the final answer of the worked solution, compared for
*symbolic equivalence* rather than string equality, because `2/4`, `0.5` and
`\frac{1}{2}` are one answer and a grader that calls two of those wrong is
measuring formatting. The answer is parsed out of LaTeX with SymPy, compared
numerically where the expected answer is a single real number and symbolically
otherwise.

Where the grader cannot decide it returns `undecidable`, not a guess. **There is
no LLM judge.** A model grading output from its own family agrees with itself for
reasons unrelated to correctness.

**LaTeX that renders** — every LaTeX string is rendered with KaTeX 0.16.21, the
version the app loads, with `throwOnError: true`, and the failures counted. The
app renders with `throwOnError: false`, which is correct for shipping — one bad
formula should not blank the screen — but it means that in production, invalid
LaTeX fails *silently*. This is the only place it is visible.

**Latency** — wall clock per request, with requests issued one at a time so
queueing does not contaminate the number.

**Cost** — input and output tokens straight from the API's own `usage` block,
priced at list rates.

## What is not measured, and why

- **Time to first token.** The app does not stream, so there is no first token to
  time. Reported as absent rather than silently equated to total latency.
- **What the user actually waits for.** The app fetches four surfaces
  concurrently; the harness runs them one at a time. The per-request latency here
  is not the number a user experiences.
- **Whether the *steps* are valid**, as opposed to whether the final answer is.
  Final answers grade cleanly; "is each step a legitimate move" does not, and the
  honest options are a hand-checked sample or nothing. This is the weakest part
  of the harness and it is not yet built.
- **Matrix- and vector-valued answers.** Scalar symbolic comparison cannot decide
  them. 2 of the 43 problems (`lin-04`, `lin-06`) are always `undecidable` and
  need a human. The grader declines rather than guessing, which is the behaviour
  we want, but it means those two problems contribute no signal.
- **Anything on a phone.** No on-device backend exists yet.

## The problem set

43 problems across seven topics — algebra, derivatives, integrals, trigonometry,
linear algebra, limits and series, probability — in
`Packages/SolvrCore/Sources/solvr-eval/problems.json`.

Every problem is synthetic and written for this harness. **No student work, no
names, no tutoring records**, here or in the demo fixtures. The 25 problems with
a single numeric answer had that answer recomputed independently before the set
was committed, rather than trusted from the author.

43 is small. It is reported as 43 rather than padded.

## Photographs, which are a different measurement

`--set camera` runs a set of photographs with their contents written down beside
them, in `docs/fixtures/camera/`. It exists because every number above this line
is about **typed** text, and the app's front door is a camera.

The model is the same on both paths. What reaches it is not: Apple's on-device
model takes no image input at all, so a photograph becomes text first, and that
step had never been measured or even recorded. A picture of `∫ 3x² + 2x + 4 dx`
produced a lesson about flatbed scanners while every table in this document
stayed green.

Three things are measured that the typed arms cannot be:

- **What was read.** `expectedText` in the manifest is what a *correct reading*
  gives, not what the model should answer, so recognition and solving are graded
  separately. They are different failures with different fixes.
- **Whether every surface of one solve was asked the same thing.** That is now a
  property of a valid run rather than something to hope for, because the bug this
  arm exists because of was four surfaces being asked four different questions.
- **What the page drew.** The device arm builds each surface's real HTML, loads
  it into a real `WKWebView` with the vendored KaTeX, and counts the strings it
  could not typeset. Rendering a string in Node tells you it parses; only that
  tells you the app drew it.

One fixture in the set must *fail*: a photograph with nothing legible in it has
to produce one honest sentence before a results screen exists. A harness that
only measured the pictures that work would not notice if that stopped being true.

Results: [evaluation-camera.md](evaluation-camera.md), from
[docs/eval-records/camera/](eval-records/camera/), including the device
transcript.

## The comparison this is set up to run

The interesting axis is not "hosted versus local". It is **constrained versus
unconstrained decoding**, and the hosted API can be either:

| arm | how the shape is obtained | repair ladder |
| --- | --- | --- |
| `anthropic` | the prompt asks: "Return ONLY valid JSON" | **load-bearing** |
| `anthropic-constrained` | `output_config.format` with a JSON Schema | unreachable *(backend since removed)* |

The prompt is **identical** between the two arms. Under structured outputs the
"no markdown fences" instructions are redundant and a production build would
delete them to save the tokens — they are deliberately left in so that exactly
one thing differs between the arms and the result can be attributed to it.

This matters beyond Solvr. The repair ladder is often described as the price of
using a hosted model. It is not: it is the price of asking *any* model for JSON
in prose. Constrained decoding is available server-side via
`output_config.format`, on-device via `FoundationModels`' guided generation — and
**not** available from `mlx_lm.server`, which accepts no `response_format`,
schema or grammar option (its only logits processors are repetition penalty and
logit bias). So the repair ladder is what makes an unconstrained *self-hosted*
model usable, which is close to the opposite of the usual framing.

**These numbers have not been collected yet.** The run costs real money against a
real key — roughly 43 problems x 3 surfaces x 2 arms — and that is the owner's
call, not the harness's. The command is below.

## Nothing hosted was ever run, and now nothing hosted can be

Stated before the numbers, because a document full of tables invites the
assumption that the tables were filled in. **No hosted evaluation was ever
executed.** The constrained-vs-unconstrained comparison described above was a
method, never a result: the command for it spent money, so it was left
deliberately awkward to run by accident, and then it was never run at all.

That is now permanent. The hosted backend has been removed from the app, so the
arm cannot be re-added without restoring the provider it drove. The honest
summary of this repository's hosted-versus-local content is therefore: a designed
comparison, published in full, with no data behind it. Anyone quoting Solvr as
evidence that on-device beats hosted — or loses to it — is quoting something that
was never measured.

**The self-hosted arm was very nearly lost the same way, and for a duller
reason.** It went out with the hosted backend, and `compare3.sh` and `arm.sh`
carried on calling `solvr-eval --backend local` with flags that had stopped
existing — so the three-arm comparison this repository publishes had become
unreproducible without anything saying so. A published result whose method is no
longer in the repository is a number with no run behind it, which is the one
thing this project is not supposed to have. The arm is back, in the `solvr-eval`
target only, with the prompts recovered verbatim because the LoRA was distilled
against those exact strings. It is not in the app and cannot be: `tools/check.sh`
asserts that the network client appears nowhere under `Sources/` except that one
directory, and that the app and the shipped library contain none.

The first local three-arm comparison was also void, and the reason is worth
recording: a port race left all three arms talking to the same server, so all
three "models" produced 129 byte-identical outputs. Byte-identical answers across
three supposedly different models is the signature to look for — the harness now
fingerprints each arm before trusting a run.

## Results so far: the pipeline, validated against the demo backend

The only backend measured to date is `demo/fixtures`, which needs no key and no
network. This is not a quality result — the demo returns the same canned answer
to every problem — it is a test that the harness discriminates:

```
| backend         | steps    | lesson   | formulas |
| demo/fixtures   | 0% (0/43)| 0% (0/43)| 0% (0/43)|
```

Zero, and correctly so: the fixtures carry raw unescaped LaTeX (`\frac`, not
`\\frac`) on purpose, so every one of them exercises the escape-repair rung. That
is the demo doing its job as a live regression test on the parser.

```
| backend       | correct    | wrong | undecidable |
| demo/fixtures | 12% (5/43) | 36    | 2           |
```

The demo answers `1` to everything. Exactly five problems in the set have the
answer 1 — `int-01`, `int-02`, `tri-04`, `tri-05`, `lim-01` — and those are
precisely the five scored correct. A grader that rubber-stamped would have
returned a high number here; this one returns 5.

LaTeX: 430 of 430 strings render. Latency: floor, since nothing leaves the
process.

## Running it

```sh
# The camera path. Needs no key and no network; the photographs are in the repo.
swift run --package-path Packages/SolvrCore solvr-eval \
  --backend on-device --set camera --images docs/fixtures/camera \
  --out eval-camera.jsonl
tools/eval/grade.sh eval-camera.jsonl

# The same on the phone, which is the only authority on the phone. See
# docs/fixtures/camera/README.md for the three devicectl lines.

# Free: no key, no network, no spend. Validates the whole pipeline.
cd Packages/SolvrCore && swift run solvr-eval --backend demo --out ../../eval-demo.jsonl

# The real thing. Needs a machine whose on-device model is downloaded and
# switched on; the harness checks once and stops rather than failing 43 times.
swift run solvr-eval --backend on-device --out ../../eval-ondevice.jsonl

# Grading and reporting are separate steps, so a saved run can be re-graded
# without running the model again.
cd ../.. && tools/eval/grade.sh eval-ondevice.jsonl
```

One-time setup for the graders:

```sh
python3 -m venv ~/.venvs/solvr-eval
~/.venvs/solvr-eval/bin/pip install sympy 'antlr4-python3-runtime==4.11'
(cd tools/eval && npm install katex@0.16.21)
```

`--limit N` runs a prefix of the set, which is the sane way to check a paid arm
works before committing to all of it.
