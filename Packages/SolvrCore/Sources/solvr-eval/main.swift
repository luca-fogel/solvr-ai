import Foundation
import SolvrCore

// A measurement harness for Solvr's backends.
//
// The point of this executable is that a claim about a backend should be a
// number with a method attached. It drives the same providers the app drives --
// that is why they live in SolvrCore -- records what happened to every response,
// and writes one JSON object per request so the grading and reporting steps can
// be re-run without paying for the requests again.
//
// It measures four things and is honest about a fifth:
//   * schema compliance, from LLMJSON.Compliance, per surface
//   * latency, wall clock, requests run one at a time so queueing does not
//     contaminate the number
//   * tokens in and out, straight from the API's own usage block
//   * the LaTeX and the final answer, emitted for the graders in tools/eval
//   * time to first token, which it does NOT measure: the app does not stream,
//     so there is no first token to time. Reported as absent rather than
//     silently equated to total latency.

// MARK: - Arguments

struct Options {
    var backend = "demo"
    var limit: Int?
    var output = "eval-results.jsonl"
    /// Which problems to run. `corpus` is the historical 43, kept as the default
    /// so an old command line still produces a comparable run.
    var set = "corpus"
    /// One ad-hoc problem, for asking "does this exact wording fail?" without
    /// editing a dataset. Two of the app's six sample problems failed on every
    /// run -- one refused, one overflowed the context window -- and finding the
    /// wording that does not is a matter of trying wordings.
    var problem: String?
    var expect: String?

    /// How many times to run each problem. Greedy decoding makes a single run
    /// reproducible, not reliable: the point of repeating is to see whether a
    /// problem is answered the same way every time.
    var repeats = 1

    /// Where the photographic fixtures live, for `--set camera`.
    var images = "docs/fixtures/camera"
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while let flag = args.first {
        args.removeFirst()
        func value() -> String {
            guard let v = args.first else {
                FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
                exit(2)
            }
            args.removeFirst()
            return v
        }
        switch flag {
        case "--backend": o.backend = value()
        case "--limit": o.limit = Int(value())
        case "--set": o.set = value()
        case "--problem": o.problem = value()
        case "--expect": o.expect = value()
        case "--repeat": o.repeats = max(1, Int(value()) ?? 1)
        case "--images": o.images = value()
        case "--out": o.output = value()
        case "--help", "-h":
            print("""
            solvr-eval --backend <demo|on-device> [--set corpus|samples|all|camera]
                       [--limit N] [--repeat N] [--images DIR] [--out file.jsonl]

            Sets:
              corpus      the 43-problem corpus in problems.json (default)
              samples     the six problems the app's topic chips insert, taken
                          from SolvrCore.SampleProblems so the measured text is
                          byte-identical to the tapped text
              all         both
              camera      photographs with known contents, read by Vision and
                          then solved -- the only arm that measures what the
                          camera path actually does. --images points at a
                          directory with a manifest.json beside the pictures.

            Backends:
              demo        bundled fixtures. No model, no network, no spend. Still
                          worth running: the fixtures are decoded through the same
                          LLMJSON ladder as everything else, so this arm measures
                          the pipeline even though it does not measure a model.
              on-device   Apple's on-device foundation model, via guided
                          generation -- the only backend the app ships.

            The hosted and self-hosted arms are gone with the backends they drove.
            The records they produced are kept, and published, in docs/eval-records/:
            a measurement does not stop being true because the code that made it
            was deleted. See docs/evaluation.md for what they say.

            Note what on-device does NOT report: input and output token counts.
            FoundationModels exposes no usage block, so those fields are null
            rather than estimated. An invented number is worse than a gap.
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown flag \(flag)\n".utf8))
            exit(2)
        }
    }
    return o
}

// MARK: - Problems

struct Problem: Decodable {
    let id: String
    let topic: String
    let problem: String
    let answer: String
    let numeric: Double?

    init(id: String, topic: String, problem: String, answer: String, numeric: Double?) {
        self.id = id
        self.topic = topic
        self.problem = problem
        self.answer = answer
        self.numeric = numeric
    }
}

struct ProblemFile: Decodable {
    let problems: [Problem]
}

/// The chip problems, as the harness sees them.
func sampleProblems() -> [Problem] {
    SampleProblems.all.map {
        Problem(id: $0.id, topic: $0.topic.lowercased(), problem: $0.text,
                answer: $0.expectedAnswer, numeric: $0.expectedNumeric)
    }
}

func loadProblems() -> [Problem] {
    guard let url = Bundle.module.url(forResource: "problems", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(ProblemFile.self, from: data)
    else {
        FileHandle.standardError.write(Data("could not load problems.json\n".utf8))
        exit(1)
    }
    return file.problems
}

// MARK: - Records

struct Record: Encodable {
    var backend: String
    var problemId: String
    var topic: String
    var surface: String
    var ok: Bool
    var latencySeconds: Double
    var inputTokens: Int?
    var outputTokens: Int?
    var timeToFirstTokenSeconds: Double?  // always nil: the app does not stream
    var wasFenced: Bool?
    var wasSliced: Bool?
    var escapesRepaired: Bool?
    var wasNormalised: Bool?
    var isClean: Bool?
    var latex: [String]
    /// How many items the surface returned -- steps, formulas, lesson sections.
    ///
    /// Schema compliance is blind to this: a single-step solution that decodes
    /// cleanly scores a perfect 100%. Thinning is a plausible fine-tuning
    /// regression, so it has to be measured separately or it hides inside a good
    /// number.
    var itemCount: Int
    var finalAnswer: String?
    var expectedAnswer: String
    var expectedNumeric: Double?
    var error: String?

    /// Which repetition this is, 1-based. Greedy decoding is reproducible in
    /// principle; whether it is in practice is a thing to measure, not assume.
    var runIndex: Int = 1

    /// The maths exactly as the model wrote it, before `MathNotation` touched it.
    ///
    /// `latex` above is the converted form -- what the app renders. Recording
    /// both is the only way to attribute a broken formula to the model or to the
    /// converter, and until this existed nobody could say which.
    var rawMath: [String] = []

    /// Fields the app discarded because they read as a sentence, not an
    /// expression. A high count here is a missing working box on screen.
    var droppedAsProse: [String] = []

    /// What `MathNotation` turned each `rawMath` string into, index-aligned with
    /// it, empty where the field was dropped for reading as prose.
    ///
    /// Recording the pair rather than two independent lists is what lets the
    /// grader answer the question that matters about the converter: did it take
    /// a string KaTeX accepted and produce one KaTeX rejects? Three shipped bugs
    /// say that is worth counting.
    var convertedMath: [String] = []

    /// **Exactly what the model was asked**, in full.
    ///
    /// New, and the reason it is new is the release this harness is measuring:
    /// four surfaces of one photographed solve were being asked four different
    /// things, and every published record in this repository was of a typed
    /// problem where the question was obviously the problem. It is not obvious
    /// on the camera path. Grouping records by `problemId` and checking that
    /// this field is constant is now a property of a valid run.
    var question: String?

    /// `typed` or `photograph+ocr`. A number from a photograph and a number
    /// from a typed problem are not the same measurement, and averaging them
    /// would hide exactly the gap this arm exists to size.
    var source: String = "typed"

    /// Camera fixtures only: what a correct reading of the photograph gives.
    var expectedText: String?

    /// True on the fixture that is supposed to be refused. A photograph with
    /// nothing legible in it must fail once, before any surface is asked.
    var refusedAsUnreadable: Bool?
}

/// Collects the provider's per-field maths traces, keyed by surface.
///
/// Stores plain strings rather than the provider's `MathTrace`: that type only
/// exists where `FoundationModels` does, and this actor has to compile on the
/// demo arm too.
actor MathTraces {
    private var raw: [String: [String]] = [:]
    private var converted: [String: [String]] = [:]
    private var dropped: [String: [String]] = [:]

    func record(surface: String, raw text: String, converted rendered: String?,
                droppedAsProse: Bool) {
        raw[surface, default: []].append(text)
        // Index-aligned with `raw`, empty where the field was dropped. The
        // alignment is the point: "did our conversion break a string that
        // rendered?" is only answerable if the before and after of the *same*
        // string can be found, and a flat list of raw strings beside a shorter
        // flat list of converted ones cannot answer it.
        converted[surface, default: []].append(rendered ?? "")
        if droppedAsProse { dropped[surface, default: []].append(text) }
    }

    /// Raw strings, their converted forms, and the ones dropped as prose.
    /// Clears as it reads, so each request sees only its own fields.
    func take(_ surface: String) -> ([String], [String], [String]) {
        (raw.removeValue(forKey: surface) ?? [],
         converted.removeValue(forKey: surface) ?? [],
         dropped.removeValue(forKey: surface) ?? [])
    }
}

/// Collects what the provider reports about each request, keyed by surface.
actor Telemetry {
    private var fixtureCompliance: [String: LLMJSON.Compliance] = [:]

    func record(_ surface: String, _ c: LLMJSON.Compliance) { fixtureCompliance[surface] = c }

    /// Compliance, input tokens, output tokens.
    ///
    /// All three are absent for the on-device arm, and that is the honest answer
    /// rather than a missing feature: guided generation never produces a string
    /// to repair, so there is no compliance ladder to report, and
    /// FoundationModels exposes no usage block, so there are no tokens to count.
    func take(_ surface: String) -> (LLMJSON.Compliance?, Int?, Int?) {
        if let c = fixtureCompliance.removeValue(forKey: surface) {
            return (c, nil, nil)
        }
        return (nil, nil, nil)
    }
}

// MARK: - Extraction
//
// What the graders need out of a response: every LaTeX string, so their validity
// can be checked by a renderer rather than by eye, and a best guess at the final
// answer, which for a worked solution is the last step that shows any working.

/// What the app actually hands KaTeX.
///
/// Not what the provider returned: `HTMLBuilder` strips the dollar delimiters
/// on the way into the page, so a string measured with them in is a string the
/// renderer never sees.
func rendered(_ latex: [String]) -> [String] {
    latex.map(MathHTML.stripDollarDelimiters).filter { !$0.isEmpty }
}

func latexAndAnswer(from steps: [StepItem]) -> ([String], String?) {
    let latex = rendered(steps.compactMap { $0.math }.filter { !$0.isEmpty })
    // The provider marks the step carrying the answer, because the model is now
    // asked for it as its own field. Falling back to "the last step" is kept for
    // solutions that predate the field, but it is a guess and it was wrong
    // exactly when the working ran long: the grader would be handed a sentence
    // like "Step 4: Conclude the solution" and return `undecidable`.
    let answerStep = steps.last(where: { $0.isFinalAnswer }) ?? steps.last
    let answer = answerStep.map { step -> String in
        if let math = step.math, !math.isEmpty { return math }
        return step.explanation
    }
    return (latex, answer)
}

func latex(from lesson: LessonContent) -> [String] {
    rendered(lesson.sections.compactMap { $0.formula }.filter { !$0.isEmpty })
}

func latex(from formulas: [FormulaItem]) -> [String] {
    rendered(formulas.map(\.formula).filter { !$0.isEmpty })
}

// MARK: - Run

let options = parseOptions()

/// A photograph that has been read, or the reason it could not be.
struct ResolvedFixture {
    let fixture: CameraFixture
    let solve: Solve?
    let failure: String?
}

/// Read every fixture once, before any model is asked anything.
///
/// This is the app's own order, and it is the point: recognition happens once,
/// up front, and what it produced is recorded next to every surface that was
/// asked about it. A run where the four surfaces of one photograph disagree is
/// a failed run, not a curiosity, and `--set camera` says so at the end.
func resolveCameraFixtures() async -> [ResolvedFixture] {
    let (dir, fixtures) = CameraFixtures.load(from: options.images)
    let builder = CameraFixtures.builder()
    var out: [ResolvedFixture] = []
    for fixture in fixtures {
        let url = dir.appendingPathComponent(fixture.file)
        guard let data = try? Data(contentsOf: url) else {
            out.append(ResolvedFixture(fixture: fixture, solve: nil,
                                       failure: "missing image \(fixture.file)"))
            continue
        }
        do {
            out.append(ResolvedFixture(fixture: fixture,
                                       solve: try await builder.photograph(data),
                                       failure: nil))
        } catch {
            out.append(ResolvedFixture(fixture: fixture, solve: nil,
                                       failure: "\(error)"))
        }
    }
    return out
}

let selected: [Problem]
if let ad = options.problem {
    selected = [Problem(id: "adhoc", topic: "adhoc", problem: ad,
                        answer: options.expect ?? "", numeric: nil)]
} else {
switch options.set {
case "corpus": selected = loadProblems()
case "samples": selected = sampleProblems()
case "all": selected = sampleProblems() + loadProblems()
case "camera": selected = []   // resolved below, from photographs
default:
    FileHandle.standardError.write(Data("unknown --set \(options.set)\n".utf8))
    exit(2)
}
}
let problems = Array(selected.prefix(options.limit ?? .max))
let telemetry = Telemetry()
let traces = MathTraces()

let provider: any SolutionProvider
switch options.backend {
case "demo":
    #if SOLVR_DEMO
    provider = FixtureSolutionProvider(latency: .zero) { surface, compliance in
        Task { await telemetry.record(surface, compliance) }
    }
    #else
    FileHandle.standardError.write(Data("""
        the demo arm is compiled out of release builds -- the fixtures ship in no
        binary a student could install. Run the harness in debug (the default) to
        use --backend demo.

        """.utf8))
    exit(1)
    #endif
case "on-device":
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *) else {
        FileHandle.standardError.write(Data("--backend on-device needs macOS 26 or newer\n".utf8))
        exit(1)
    }
    let onDevice = OnDeviceProvider(traceMath: { t in
        Task { await traces.record(surface: t.surface, raw: t.raw,
                                   converted: t.rendered,
                                   droppedAsProse: t.droppedAsProse) }
    })
    // Availability is checked once, before the run, so an ineligible machine
    // fails in one line rather than in 43 identical ones.
    if let unavailable = onDevice.availability {
        let reason = unavailable.errorDescription ?? "unknown"
        FileHandle.standardError.write(Data("""
            on-device model unavailable: \(reason)

            This is a property of the machine, not of the harness. The model has to
            be downloaded and Apple Intelligence switched on before it can answer.

            """.utf8))
        exit(1)
    }
    provider = onDevice
    #else
    FileHandle.standardError.write(Data("this build has no FoundationModels\n".utf8))
    exit(1)
    #endif
default:
    FileHandle.standardError.write(Data("unknown backend \(options.backend)\n".utf8))
    exit(2)
}

FileManager.default.createFile(atPath: options.output, contents: Data())
guard let out = FileHandle(forWritingAtPath: options.output) else {
    FileHandle.standardError.write(Data("cannot write \(options.output)\n".utf8))
    exit(1)
}
let encoder = JSONEncoder()
encoder.outputFormatting = []

func emit(_ record: Record) {
    guard let line = try? encoder.encode(record) else { return }
    out.write(line)
    out.write(Data("\n".utf8))
}

// MARK: - One problem, three surfaces

/// Everything a record needs that is not about the response.
struct Subject {
    let id: String
    let topic: String
    /// The string the model is asked. For a photograph this is what Vision read.
    let question: String
    let source: String
    let expectedAnswer: String
    let expectedNumeric: Double?
    /// Camera fixtures only: what a correct reading would have produced.
    let expectedText: String?
}

/// Ask one subject for the three graded surfaces, in order.
///
/// Every record carries `question` -- the exact string the model was given.
/// That field is the whole reason this function exists in one copy instead of
/// three: the bug this release is about was four surfaces being asked four
/// different things, and a harness that could not have detected it is a harness
/// that was measuring the wrong thing.
func runSurfaces(_ subject: Subject, run: Int) async {
    func record(_ surface: String, ok: Bool, latency: Double, latex: [String],
                itemCount: Int, finalAnswer: String?, error: String?,
                compliance: LLMJSON.Compliance?, tokens: (Int?, Int?),
                rawMath: [String], dropped: [String], converted: [String] = []) {
        emit(Record(backend: provider.identifier, problemId: subject.id,
                    topic: subject.topic, surface: surface, ok: ok,
                    latencySeconds: latency,
                    inputTokens: tokens.0, outputTokens: tokens.1,
                    timeToFirstTokenSeconds: nil,
                    wasFenced: compliance?.wasFenced, wasSliced: compliance?.wasSliced,
                    escapesRepaired: compliance?.escapesRepaired,
                    wasNormalised: compliance?.wasNormalised, isClean: compliance?.isClean,
                    latex: latex, itemCount: itemCount, finalAnswer: finalAnswer,
                    expectedAnswer: subject.expectedAnswer,
                    expectedNumeric: subject.expectedNumeric,
                    error: error, runIndex: run, rawMath: rawMath,
                    droppedAsProse: dropped, convertedMath: converted,
                    question: subject.question, source: subject.source,
                    expectedText: subject.expectedText))
    }

    // Steps first: it is the surface the answer grading depends on.
    do {
        let clock = Date()
        let steps = try await provider.steps(for: subject.question)
        let latency = Date().timeIntervalSince(clock)
        let (tex, answer) = latexAndAnswer(from: steps)
        let (compliance, tokensIn, tokensOut) = await telemetry.take("steps")
        let (rawTex, convertedTex, droppedTex) = await traces.take("steps")
        record("steps", ok: true, latency: latency, latex: tex, itemCount: steps.count,
               finalAnswer: answer, error: nil, compliance: compliance,
               tokens: (tokensIn, tokensOut), rawMath: rawTex, dropped: droppedTex,
               converted: convertedTex)
    } catch {
        record("steps", ok: false, latency: 0, latex: [], itemCount: 0,
               finalAnswer: nil, error: "\(error)", compliance: nil,
               tokens: (nil, nil), rawMath: [], dropped: [])
    }

    do {
        let clock = Date()
        let lesson = try await provider.lesson(for: subject.question)
        let latency = Date().timeIntervalSince(clock)
        let (compliance, tokensIn, tokensOut) = await telemetry.take("lesson")
        let (rawTex, convertedTex, droppedTex) = await traces.take("lesson")
        record("lesson", ok: true, latency: latency, latex: latex(from: lesson),
               itemCount: lesson.sections.count, finalAnswer: nil, error: nil,
               compliance: compliance, tokens: (tokensIn, tokensOut),
               rawMath: rawTex, dropped: droppedTex, converted: convertedTex)
    } catch {
        record("lesson", ok: false, latency: 0, latex: [], itemCount: 0,
               finalAnswer: nil, error: "\(error)", compliance: nil,
               tokens: (nil, nil), rawMath: [], dropped: [])
    }

    do {
        let clock = Date()
        let formulas = try await provider.formulas(for: subject.question)
        let latency = Date().timeIntervalSince(clock)
        let (compliance, tokensIn, tokensOut) = await telemetry.take("formulas")
        let (rawTex, convertedTex, droppedTex) = await traces.take("formulas")
        record("formulas", ok: true, latency: latency, latex: latex(from: formulas),
               itemCount: formulas.count, finalAnswer: nil, error: nil,
               compliance: compliance, tokens: (tokensIn, tokensOut),
               rawMath: rawTex, dropped: droppedTex, converted: convertedTex)
    } catch {
        record("formulas", ok: false, latency: 0, latex: [], itemCount: 0,
               finalAnswer: nil, error: "\(error)", compliance: nil,
               tokens: (nil, nil), rawMath: [], dropped: [])
    }
}

// MARK: - Run

var completed = 0

if options.set == "camera" {
    let resolved = await resolveCameraFixtures()
    print("backend: \(provider.identifier)")
    print("fixtures: \(resolved.count) photographs from \(options.images)")
    print("writing:  \(options.output)")
    print("note:     each photograph is read once, before any surface is asked")
    print("")

    var misread: [String] = []
    for item in resolved {
        let expectUnreadable = item.fixture.expectUnreadable ?? false

        guard let solve = item.solve else {
            // A fixture that could not be read. For the one that is *meant* to
            // be unreadable this is the pass condition; for any other it is the
            // failure the camera path is most likely to have.
            emit(Record(backend: provider.identifier, problemId: item.fixture.id,
                        topic: item.fixture.topic, surface: "recognition",
                        ok: expectUnreadable, latencySeconds: 0,
                        inputTokens: nil, outputTokens: nil, timeToFirstTokenSeconds: nil,
                        wasFenced: nil, wasSliced: nil, escapesRepaired: nil,
                        wasNormalised: nil, isClean: nil, latex: [], itemCount: 0,
                        finalAnswer: nil, expectedAnswer: item.fixture.answer,
                        expectedNumeric: item.fixture.numeric,
                        error: item.failure, runIndex: 1,
                        question: nil, source: "photograph+ocr",
                        expectedText: item.fixture.expectedText,
                        refusedAsUnreadable: true))
            completed += 1
            FileHandle.standardError.write(
                Data("\r\(completed)/\(resolved.count) fixtures".utf8))
            continue
        }

        if expectUnreadable {
            misread.append("\(item.fixture.id) was expected to be unreadable and was read as "
                           + "\"\(solve.question)\"")
        }

        // The recognition itself is a record, separate from the solving. A run
        // that cannot tell "Vision misread it" from "the model got it wrong" is
        // not measuring the camera path, it is averaging over it.
        emit(Record(backend: provider.identifier, problemId: item.fixture.id,
                    topic: item.fixture.topic, surface: "recognition", ok: true,
                    latencySeconds: 0, inputTokens: nil, outputTokens: nil,
                    timeToFirstTokenSeconds: nil, wasFenced: nil, wasSliced: nil,
                    escapesRepaired: nil, wasNormalised: nil, isClean: nil,
                    latex: [], itemCount: 0, finalAnswer: nil,
                    expectedAnswer: item.fixture.answer,
                    expectedNumeric: item.fixture.numeric, error: nil, runIndex: 1,
                    question: solve.question, source: solve.source.name,
                    expectedText: item.fixture.expectedText,
                    refusedAsUnreadable: false))

        for run in 1...options.repeats {
            await runSurfaces(Subject(id: item.fixture.id, topic: item.fixture.topic,
                                      question: solve.question,
                                      source: solve.source.name,
                                      expectedAnswer: item.fixture.answer,
                                      expectedNumeric: item.fixture.numeric,
                                      expectedText: item.fixture.expectedText),
                              run: run)
        }
        completed += 1
        FileHandle.standardError.write(
            Data("\r\(completed)/\(resolved.count) fixtures".utf8))
    }
    FileHandle.standardError.write(Data("\n".utf8))
    for line in misread {
        FileHandle.standardError.write(Data("WARNING: \(line)\n".utf8))
    }
} else {
    print("backend: \(provider.identifier)")
    print("problems: \(problems.count) (\(options.set))   repeats: \(options.repeats)   "
          + "surfaces: steps, lesson, formulas")
    print("writing:  \(options.output)")
    print("note:     requests run one at a time so latency is not distorted by queueing")
    print("")

    for problem in problems {
        for run in 1...options.repeats {
            await runSurfaces(Subject(id: problem.id, topic: problem.topic,
                                      question: problem.problem, source: "typed",
                                      expectedAnswer: problem.answer,
                                      expectedNumeric: problem.numeric,
                                      expectedText: nil),
                              run: run)
            completed += 1
            FileHandle.standardError.write(
                Data("\r\(completed)/\(problems.count * options.repeats) runs".utf8))
        }
    }
    FileHandle.standardError.write(Data("\n".utf8))
}

try? out.close()
print("done. next: tools/eval/grade.sh \(options.output)")
