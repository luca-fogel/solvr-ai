import Foundation
import SolvrCore

// Generates the fine-tuning dataset by distilling the hosted model.
//
// Two properties make this worth being a Swift tool rather than a script.
//
// The prompt in every training example is the *exact* string the app sends, taken
// from `AnthropicPrompts` rather than retyped, because a model fine-tuned on a
// paraphrase of the prompt is fine-tuned for a prompt the app never sends. And
// the target is produced by encoding the decoded domain model, so every target is
// by construction something the app can decode -- there is no way for this to emit
// a training example the app would then fail to parse.
//
// This is distillation from a hosted model, stated plainly because it is the
// method and because people lie about it. Everything it runs on is synthetic and
// disjoint from the evaluation set.

struct Options {
    var problemsPath = "tools/finetune/problems.json"
    var output = "tools/finetune/data/raw.jsonl"
    var model = "claude-opus-5"
    var keyEnv = "ANTHROPIC_API_KEY"
    var limit: Int?
    var surfaces = ["steps", "lesson", "formulas", "videos"]
    var confirmSpend = false
    var concurrency = 4
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while let flag = args.first {
        args.removeFirst()
        func value() -> String {
            guard let v = args.first else {
                FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8)); exit(2)
            }
            args.removeFirst(); return v
        }
        switch flag {
        case "--problems": o.problemsPath = value()
        case "--out": o.output = value()
        case "--model": o.model = value()
        case "--key-env": o.keyEnv = value()
        case "--limit": o.limit = Int(value())
        case "--surfaces": o.surfaces = value().split(separator: ",").map(String.init)
        case "--concurrency": o.concurrency = Int(value()) ?? o.concurrency
        case "--confirm-spend": o.confirmSpend = true
        case "--help", "-h":
            print("""
            solvr-distill [--limit N] [--surfaces steps,lesson,formulas,videos]
                          [--model ID] [--out file.jsonl] --confirm-spend

            Generates fine-tuning targets by asking the hosted model the app's own
            prompts, with output_config.format so the shape is guaranteed.

            Billed. Prints an estimate and refuses to run without --confirm-spend,
            because it is not this tool's money.
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("unknown flag \(flag)\n".utf8)); exit(2)
        }
    }
    return o
}

struct Problem: Decodable {
    let id: String
    let topic: String
    let problem: String
}

struct ProblemFile: Decodable { let problems: [Problem] }

let options = parse()

guard let data = FileManager.default.contents(atPath: options.problemsPath),
      let file = try? JSONDecoder().decode(ProblemFile.self, from: data) else {
    FileHandle.standardError.write(Data("cannot read \(options.problemsPath)\n".utf8))
    exit(1)
}
let problems = Array(file.problems.prefix(options.limit ?? .max))

guard let key = ProcessInfo.processInfo.environment[options.keyEnv], !key.isEmpty else {
    FileHandle.standardError.write(Data("""
        \(options.keyEnv) is not set.

        This tool makes real, billed requests. Export a key deliberately:
          export \(options.keyEnv)=...

        """.utf8))
    exit(1)
}

// Rough pre-flight estimate, so the number is seen before it is spent rather
// than after. Per-call figures are the observed averages for these prompts.
let calls = problems.count * options.surfaces.count
let estimatedInput = Double(calls) * 700
let estimatedOutput = Double(calls) * 900
let price: (Double, Double) = {
    switch options.model {
    case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6": return (5, 25)
    case "claude-sonnet-5", "claude-sonnet-4-6": return (3, 15)
    case "claude-haiku-4-5": return (1, 5)
    case "claude-fable-5": return (10, 50)
    default: return (5, 25)
    }
}()
let estimate = (estimatedInput * price.0 + estimatedOutput * price.1) / 1e6

print("""
    model:      \(options.model)
    problems:   \(problems.count)
    surfaces:   \(options.surfaces.joined(separator: ", "))
    requests:   \(calls)
    estimate:   ~$\(String(format: "%.2f", estimate))  (rough; actual is reported from usage)
    output:     \(options.output)
    """)

guard options.confirmSpend else {
    print("""

        Not running. Re-run with --confirm-spend to authorise the requests above.
        """)
    exit(0)
}
print("")

/// Structured outputs on, so the response shape is guaranteed and the target
/// never needs repairing before it becomes training data.
let provider = AnthropicProvider(
    configuration: .init(model: options.model, maxTokens: 3000, usesStructuredOutputs: true),
    apiKey: { key })

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

/// One training example: the prompt the app sends, and a target the app can decode.
struct Example: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let messages: [Message]
}

actor Writer {
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private(set) var written = 0
    private(set) var failed = 0

    init(path: String, encoder: JSONEncoder) throws {
        FileManager.default.createFile(atPath: path, contents: Data())
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw SolverError.invalidResponse
        }
        self.handle = handle
        self.encoder = encoder
    }

    func write(prompt: String, target: String, surface: String, problemID: String) {
        let example = Example(messages: [.init(role: "user", content: prompt),
                                        .init(role: "assistant", content: target)])
        guard let line = try? encoder.encode(example) else { failed += 1; return }
        handle.write(line)
        handle.write(Data("\n".utf8))
        written += 1
    }

    func recordFailure() { failed += 1 }
    func close() { try? handle.close() }
}

let writer = try Writer(path: options.output, encoder: encoder)

/// Encode a decoded value back to canonical JSON. The target is therefore
/// guaranteed decodable by the app: it just came out of the app's own type.
func target<T: Encodable>(_ value: T) throws -> String {
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw SolverError.invalidResponse
    }
    return string
}

func distill(_ problem: Problem, surface: String) async throws -> (String, String) {
    let input = ProblemInput.text(problem.problem)
    switch surface {
    case "steps":
        return (AnthropicPrompts.steps(input), try target(try await provider.steps(for: input)))
    case "lesson":
        return (AnthropicPrompts.lesson(input), try target(try await provider.lesson(for: input)))
    case "formulas":
        return (AnthropicPrompts.formulas(input), try target(try await provider.formulas(for: input)))
    case "videos":
        return (AnthropicPrompts.videos(input), try target(try await provider.videos(for: input)))
    default:
        throw SolverError.apiError("unknown surface \(surface)")
    }
}

let started = Date()
var completed = 0
let total = calls

// Bounded concurrency: the provider's own queue caps in-flight requests at four,
// so going wider here only builds a backlog.
await withTaskGroup(of: Void.self) { group in
    var iterator = problems.flatMap { problem in
        options.surfaces.map { (problem, $0) }
    }.makeIterator()

    func addNext() {
        guard let (problem, surface) = iterator.next() else { return }
        group.addTask {
            do {
                let (prompt, target) = try await distill(problem, surface: surface)
                await writer.write(prompt: prompt, target: target,
                                   surface: surface, problemID: problem.id)
            } catch {
                await writer.recordFailure()
                FileHandle.standardError.write(
                    Data("\n\(problem.id)/\(surface): \(error)\n".utf8))
            }
        }
    }

    for _ in 0..<options.concurrency { addNext() }
    while await group.next() != nil {
        completed += 1
        let elapsed = Date().timeIntervalSince(started)
        let rate = Double(completed) / max(elapsed, 0.001)
        let remaining = Double(total - completed) / max(rate, 0.001)
        FileHandle.standardError.write(Data(
            String(format: "\r%d/%d  %.1f req/s  ~%.0fs left     ",
                   completed, total, rate, remaining).utf8))
        addNext()
    }
}
FileHandle.standardError.write(Data("\n".utf8))

let written = await writer.written
let failed = await writer.failed
await writer.close()

print("""
    written:  \(written) examples
    failed:   \(failed)
    elapsed:  \(String(format: "%.0fs", Date().timeIntervalSince(started)))
    output:   \(options.output)

    next: tools/finetune/prepare_data.py \(options.output)
    """)
