import Foundation
import SolvrCore

/// An OpenAI-compatible endpoint you run yourself, for the measurement tool only.
///
/// **This is not in the app and cannot be.** It lives in the `solvr-eval`
/// executable target, which is a command-line tool that is never installed on a
/// phone; the app links `SolvrCore`, and `SolvrCore` has no network client in it.
/// `tools/check.sh` asserts exactly that, and says so in the one place it is
/// scoped.
///
/// It comes back because the fine-tune cannot be measured without it. The
/// published three-arm comparison in `docs/evaluation-local.md` was produced by
/// this provider against `mlx_lm.server`, and when the backend was deleted the
/// comparison silently stopped being reproducible: `compare3.sh` and `arm.sh`
/// went on calling `--backend local` with flags that no longer existed. A
/// published result whose method has been removed from the repository is a
/// number without a run behind it, which is the one thing this project is not
/// supposed to have.
///
/// What is deliberately *not* restored: image input, the title surface, and the
/// constrained arm. `mlx_lm.server` accepts no `response_format`, no JSON schema
/// and no grammar -- its only logits processors are repetition penalty and logit
/// bias -- so the constrained arm could never have run against it, and the
/// hosted endpoint it was written for is gone. That makes this **the one backend
/// whose decoding cannot be constrained**, and therefore the one where the
/// `LLMJSON` repair ladder is genuinely load-bearing rather than dead code.
final class LocalServerProvider: SolutionProvider {

    struct Configuration: Sendable {
        /// e.g. `http://127.0.0.1:8131` for a loopback `mlx_lm.server`.
        var baseURL: URL
        var model: String
        var maxTokens: Int
        var timeout: TimeInterval
        /// Zero, which buys reproducible evaluation runs. Omittable because some
        /// hosted models reject it -- Kimi K3 returns "only 1 is allowed for this
        /// model" and a 400 -- and determinism is then simply unavailable, which
        /// is a fact to record rather than paper over.
        var temperature: Double?
        /// One. A single GPU serialises anyway, so more in flight just means each
        /// request takes longer and the latency column stops meaning anything.
        var concurrency: Int

        init(baseURL: URL, model: String = "local", maxTokens: Int = 2048,
             timeout: TimeInterval = 300, temperature: Double? = 0,
             concurrency: Int = 1) {
            self.baseURL = baseURL
            self.model = model
            self.maxTokens = maxTokens
            self.timeout = timeout
            self.temperature = temperature
            self.concurrency = concurrency
        }
    }

    /// Surface, latency, tokens, and what the repair ladder had to do.
    struct Measurement: Sendable {
        let surface: String
        let latency: TimeInterval
        let inputTokens: Int?
        let outputTokens: Int?
        let compliance: LLMJSON.Compliance?
        let failure: String?
    }

    typealias Observer = @Sendable (Measurement) -> Void

    private let configuration: Configuration
    private let session: URLSession
    private let observe: Observer?
    private let queue: RequestQueue
    private let lastCompliance = ComplianceSlot()

    init(configuration: Configuration,
         session: URLSession = .shared,
         observe: Observer? = nil) {
        self.configuration = configuration
        self.session = session
        self.observe = observe
        self.queue = RequestQueue(maxConcurrent: configuration.concurrency)
    }

    // MARK: - SolutionProvider

    var identifier: String { "local/\(configuration.model)/unconstrained" }
    var maxConcurrentRequests: Int { configuration.concurrency }

    /// A URL is all it takes to be configured. Whether anything is *listening* is
    /// a question only a request can answer, and pretending otherwise would make
    /// a sleeping Mac look like a misconfiguration.
    var isConfigured: Bool { true }

    // MARK: - Surfaces

    func lesson(for question: String) async throws -> LessonContent {
        let raw = try await complete(DistilledPrompts.lesson(question), surface: "lesson")
        return try decode(LessonContent.self, from: raw, surface: "lesson")
    }

    func steps(for question: String) async throws -> [StepItem] {
        let raw = try await complete(DistilledPrompts.steps(question), surface: "steps")
        return try decodeList(StepItem.self, from: raw, surface: "steps")
    }

    func formulas(for question: String) async throws -> [FormulaItem] {
        let raw = try await complete(DistilledPrompts.formulas(question), surface: "formulas")
        return try decodeList(FormulaItem.self, from: raw, surface: "formulas")
    }

    func videos(for question: String) async throws -> [VideoItem] {
        let raw = try await complete(DistilledPrompts.videos(question), surface: "videos")
        return try decodeList(VideoItem.self, from: raw, surface: "videos")
    }

    func chatReply(to message: String, about question: String,
                   history: [ChatMessage]) async throws -> String {
        var messages: [[String: String]] = [
            ["role": "system", "content": DistilledPrompts.chatSystem(question)]
        ]
        messages += history.map { ["role": $0.role.rawValue, "content": $0.content] }
        messages.append(["role": "user", "content": message])
        return try await complete(messages: messages, surface: "chat").text
    }

    // MARK: - Decoding
    //
    // Through the full repair ladder, because nothing is constraining this
    // model's output. This is the backend the ladder exists for.

    private func decode<T: Decodable>(_ type: T.Type, from raw: String,
                                      surface: String) throws -> T {
        guard let decoded = LLMJSON.decode(type, from: raw) else {
            report(surface: surface, latency: 0, input: nil, output: nil,
                   compliance: nil, failure: "could not parse response")
            throw SolverError.decodingFailed(context: "\(surface): could not parse response")
        }
        lastCompliance.set(decoded.compliance)
        return decoded.value
    }

    private func decodeList<Element: Decodable>(_ element: Element.Type, from raw: String,
                                                surface: String) throws -> [Element] {
        guard let decoded = LLMJSON.decodeList(Element.self, from: raw) else {
            report(surface: surface, latency: 0, input: nil, output: nil,
                   compliance: nil, failure: "could not parse response")
            throw SolverError.decodingFailed(context: "\(surface): could not parse response")
        }
        lastCompliance.set(decoded.compliance)
        return decoded.value
    }

    // MARK: - The request

    private struct Completion {
        let text: String
        let inputTokens: Int?
        let outputTokens: Int?
    }

    private func complete(_ prompt: String, surface: String) async throws -> String {
        try await complete(messages: [["role": "user", "content": prompt]],
                           surface: surface).text
    }

    private func complete(messages: [[String: String]],
                          surface: String) async throws -> Completion {
        try await queue.withSlot {
            let started = Date()
            do {
                let completion = try await self.perform(messages: messages)
                self.report(surface: surface,
                            latency: Date().timeIntervalSince(started),
                            input: completion.inputTokens,
                            output: completion.outputTokens,
                            compliance: self.lastCompliance.take(), failure: nil)
                return completion
            } catch {
                self.report(surface: surface,
                            latency: Date().timeIntervalSince(started),
                            input: nil, output: nil, compliance: nil,
                            failure: "\(error)")
                throw error
            }
        }
    }

    private func perform(messages: [[String: String]]) async throws -> Completion {
        var request = URLRequest(url: Self.completionsURL(configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = configuration.timeout
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "max_tokens": configuration.maxTokens,
            "stream": false,
        ]
        if let temperature = configuration.temperature {
            body["temperature"] = temperature
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                // The common case by far: the server is not running yet.
                throw SolverError.backendUnavailable(
                    reason: "Could not reach \(configuration.baseURL.absoluteString). "
                          + "Is the model serving?")
            default:
                throw SolverError.apiError(urlError.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw SolverError.invalidResponse
        }
        guard http.statusCode == 200 else {
            // The body, not just the code. An OpenAI-compatible endpoint says
            // *why* it refused, and discarding that turns a one-line fix into a
            // hunt.
            let parsed = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: Any] }
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String }
            let detail = parsed ?? String(data: data.prefix(300), encoding: .utf8) ?? "no body"
            throw SolverError.apiError("HTTP \(http.statusCode): \(detail)")
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let choice = (root?["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]

        // A reasoning model splits its response in two: the chain of thought
        // under `reasoning_content`, the answer under `content`.
        let content = (message?["content"] as? String) ?? ""
        let reasoning = (message?["reasoning_content"] as? String)
            ?? (message?["reasoning"] as? String) ?? ""
        let text = content.isEmpty ? reasoning : content
        guard !text.isEmpty else { throw SolverError.invalidResponse }

        let usage = root?["usage"] as? [String: Any]
        return Completion(text: text,
                          inputTokens: usage?["prompt_tokens"] as? Int,
                          outputTokens: usage?["completion_tokens"] as? Int)
    }

    /// Tolerate a base URL given with or without the `/v1` suffix.
    ///
    /// Both spellings are in the wild, and blindly appending produces
    /// `/v1/v1/chat/completions`, which 404s in a way that looks like the server
    /// is down.
    static func completionsURL(_ base: URL) -> URL {
        var path = base.path
        while path.hasSuffix("/") { path.removeLast() }
        let suffix = path.hasSuffix("/v1") ? "chat/completions" : "v1/chat/completions"
        return base.appendingPathComponent(suffix)
    }

    private func report(surface: String, latency: TimeInterval,
                        input: Int?, output: Int?,
                        compliance: LLMJSON.Compliance?, failure: String?) {
        observe?(Measurement(surface: surface, latency: latency,
                             inputTokens: input, outputTokens: output,
                             compliance: compliance, failure: failure))
    }
}

/// A one-slot mailbox. `decode` learns the compliance record but does not know
/// the latency; the request site knows the latency but not the compliance. This
/// hands one to the other without threading a parameter through every surface.
private final class ComplianceSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var value: LLMJSON.Compliance?

    func set(_ compliance: LLMJSON.Compliance) {
        lock.lock(); value = compliance; lock.unlock()
    }

    func take() -> LLMJSON.Compliance? {
        lock.lock(); defer { value = nil; lock.unlock() }
        return value
    }
}
