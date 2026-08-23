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
        case "--out": o.output = value()
        case "--help", "-h":
            print("""
            solvr-eval --backend <demo|on-device> [--limit N] [--out file.jsonl]

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
}

struct ProblemFile: Decodable {
    let problems: [Problem]
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

func latexAndAnswer(from steps: [StepItem]) -> ([String], String?) {
    let latex = steps.compactMap { $0.math }.filter { !$0.isEmpty }
    let answer = steps.last.map { step -> String in
        if let math = step.math, !math.isEmpty { return math }
        return step.explanation
    }
    return (latex, answer)
}

func latex(from lesson: LessonContent) -> [String] {
    lesson.sections.compactMap { $0.formula }.filter { !$0.isEmpty }
}

func latex(from formulas: [FormulaItem]) -> [String] {
    formulas.map(\.formula).filter { !$0.isEmpty }
}

// MARK: - Run

let options = parseOptions()
let problems = Array(loadProblems().prefix(options.limit ?? .max))
let telemetry = Telemetry()

let provider: any SolutionProvider
switch options.backend {
case "demo":
    provider = FixtureSolutionProvider(latency: .zero) { surface, compliance in
        Task { await telemetry.record(surface, compliance) }
    }
case "on-device":
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, *) else {
        FileHandle.standardError.write(Data("--backend on-device needs macOS 26 or newer\n".utf8))
        exit(1)
    }
    let onDevice = OnDeviceProvider()
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

print("backend: \(provider.identifier)")
print("problems: \(problems.count)   surfaces: steps, lesson, formulas")
print("writing:  \(options.output)")
print("note:     requests run one at a time so latency is not distorted by queueing")
print("")

var completed = 0
for problem in problems {
    let input = ProblemInput.text(problem.problem)

    // Steps first: it is the surface the answer grading depends on.
    do {
        let clock = Date()
        let steps = try await provider.steps(for: input)
        let latency = Date().timeIntervalSince(clock)
        let (tex, answer) = latexAndAnswer(from: steps)
        let (compliance, input_, output_) = await telemetry.take("steps")
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "steps", ok: true, latencySeconds: latency,
                    inputTokens: input_, outputTokens: output_, timeToFirstTokenSeconds: nil,
                    wasFenced: compliance?.wasFenced, wasSliced: compliance?.wasSliced,
                    escapesRepaired: compliance?.escapesRepaired,
                    wasNormalised: compliance?.wasNormalised, isClean: compliance?.isClean,
                    latex: tex, itemCount: steps.count, finalAnswer: answer,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: nil))
    } catch {
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "steps", ok: false, latencySeconds: 0,
                    inputTokens: nil, outputTokens: nil, timeToFirstTokenSeconds: nil,
                    wasFenced: nil, wasSliced: nil, escapesRepaired: nil,
                    wasNormalised: nil, isClean: nil, latex: [], itemCount: 0,
                    finalAnswer: nil,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: "\(error)"))
    }

    do {
        let clock = Date()
        let lesson = try await provider.lesson(for: input)
        let latency = Date().timeIntervalSince(clock)
        let (compliance, input_, output_) = await telemetry.take("lesson")
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "lesson", ok: true, latencySeconds: latency,
                    inputTokens: input_, outputTokens: output_, timeToFirstTokenSeconds: nil,
                    wasFenced: compliance?.wasFenced, wasSliced: compliance?.wasSliced,
                    escapesRepaired: compliance?.escapesRepaired,
                    wasNormalised: compliance?.wasNormalised, isClean: compliance?.isClean,
                    latex: latex(from: lesson), itemCount: lesson.sections.count,
                    finalAnswer: nil,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: nil))
    } catch {
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "lesson", ok: false, latencySeconds: 0,
                    inputTokens: nil, outputTokens: nil, timeToFirstTokenSeconds: nil,
                    wasFenced: nil, wasSliced: nil, escapesRepaired: nil,
                    wasNormalised: nil, isClean: nil, latex: [], itemCount: 0,
                    finalAnswer: nil,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: "\(error)"))
    }

    do {
        let clock = Date()
        let formulas = try await provider.formulas(for: input)
        let latency = Date().timeIntervalSince(clock)
        let (compliance, input_, output_) = await telemetry.take("formulas")
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "formulas", ok: true, latencySeconds: latency,
                    inputTokens: input_, outputTokens: output_, timeToFirstTokenSeconds: nil,
                    wasFenced: compliance?.wasFenced, wasSliced: compliance?.wasSliced,
                    escapesRepaired: compliance?.escapesRepaired,
                    wasNormalised: compliance?.wasNormalised, isClean: compliance?.isClean,
                    latex: latex(from: formulas), itemCount: formulas.count,
                    finalAnswer: nil,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: nil))
    } catch {
        emit(Record(backend: provider.identifier, problemId: problem.id, topic: problem.topic,
                    surface: "formulas", ok: false, latencySeconds: 0,
                    inputTokens: nil, outputTokens: nil, timeToFirstTokenSeconds: nil,
                    wasFenced: nil, wasSliced: nil, escapesRepaired: nil,
                    wasNormalised: nil, isClean: nil, latex: [], itemCount: 0,
                    finalAnswer: nil,
                    expectedAnswer: problem.answer, expectedNumeric: problem.numeric,
                    error: "\(error)"))
    }

    completed += 1
    FileHandle.standardError.write(Data("\r\(completed)/\(problems.count) problems".utf8))
}
FileHandle.standardError.write(Data("\n".utf8))
try? out.close()
print("done. next: tools/eval/grade.sh \(options.output)")
