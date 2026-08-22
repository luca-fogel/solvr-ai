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
    var model = "claude-opus-5"
    var keyEnv = "ANTHROPIC_API_KEY"
    var maxTokens = 2048
    var baseURL: String?
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
        case "--model": o.model = value()
        case "--key-env": o.keyEnv = value()
        case "--max-tokens": o.maxTokens = Int(value()) ?? o.maxTokens
        case "--base-url": o.baseURL = value()
        case "--help", "-h":
            print("""
            solvr-eval --backend <demo|anthropic|anthropic-constrained>
                       [--limit N] [--out file.jsonl] [--model ID]
                       [--key-env VAR] [--max-tokens N]

            Backends:
              demo                    bundled fixtures, no key, no network, no spend
              local                   an OpenAI-compatible endpoint you run, via
                                      --base-url and --model. This is how the
                                      fine-tuned model is measured, and the one
                                      backend that cannot be schema-constrained
                                      by mlx_lm.server -- so the repair ladder is
                                      load-bearing here and nowhere else.
              anthropic               the hosted API as the app calls it today,
                                      asking the prompt for JSON
              anthropic-constrained   the same prompt plus output_config.format,
                                      so the API guarantees the shape

            The two anthropic arms differ in exactly one thing: the decoding
            mechanism. The prompt is identical, deliberately, so the comparison
            measures one change rather than two.
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
    private var latest: [String: AnthropicProvider.Measurement] = [:]
    private var fixtureCompliance: [String: LLMJSON.Compliance] = [:]

    func record(_ m: AnthropicProvider.Measurement) { latest[m.surface] = m }
    func record(_ surface: String, _ c: LLMJSON.Compliance) { fixtureCompliance[surface] = c }

    func take(_ surface: String) -> (LLMJSON.Compliance?, Int?, Int?) {
        if let m = latest.removeValue(forKey: surface) {
            return (m.compliance, m.inputTokens, m.outputTokens)
        }
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
case "anthropic", "anthropic-constrained":
    guard let key = ProcessInfo.processInfo.environment[options.keyEnv], !key.isEmpty else {
        FileHandle.standardError.write(Data("""
            \(options.keyEnv) is not set.

            This backend makes real, billed requests. Export the key deliberately:
              export \(options.keyEnv)=...
            Or run --backend demo, which measures the whole pipeline for free.

            """.utf8))
        exit(1)
    }
    provider = AnthropicProvider(
        configuration: .init(model: options.model,
                             maxTokens: options.maxTokens,
                             usesStructuredOutputs: options.backend == "anthropic-constrained"),
        apiKey: { key },
        isOnline: { true },
        observe: { m in Task { await telemetry.record(m) } })
case "local", "local-constrained":
    guard let raw = options.baseURL, let url = URL(string: raw) else {
        FileHandle.standardError.write(Data("--backend local requires --base-url\n".utf8))
        exit(1)
    }
    provider = LocalServerProvider(
        configuration: .init(baseURL: url,
                             model: options.model,
                             maxTokens: options.maxTokens,
                             timeout: 300,
                             bearerToken: ProcessInfo.processInfo
                                 .environment["SOLVR_LOCAL_TOKEN"],
                             usesResponseFormat: options.backend == "local-constrained"),
        observe: { m in Task { await telemetry.record(m) } })
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
