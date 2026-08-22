import Foundation

/// Solvr against an OpenAI-compatible endpoint you run yourself.
///
/// This is where the fine-tuned model lives, and it is the backend that makes the
/// project's central point concrete. `mlx_lm.server` accepts no `response_format`,
/// no JSON schema and no grammar -- its only logits processors are repetition
/// penalty and logit bias -- so **this is the one backend whose decoding cannot be
/// constrained**, and therefore the one where the `LLMJSON` repair ladder is
/// genuinely load-bearing rather than dead code.
///
/// The prompts are the hosted ones, unchanged, because that is what the fine-tune
/// was distilled against. A model trained on `AnthropicPrompts.steps` and then
/// asked something paraphrased is being asked a question it was not trained for.
public final class LocalServerProvider: SolutionProvider {

    public struct Configuration: Sendable {
        /// e.g. `http://127.0.0.1:8131` for a loopback `mlx_lm.server`, or a
        /// `https://…ts.net` hostname fronted by `tailscale serve`.
        ///
        /// Configuration, never a compiled constant: a home hostname or a tailnet
        /// address does not belong in a repository.
        public var baseURL: URL
        public var model: String
        public var maxTokens: Int
        public var timeout: TimeInterval

        /// A local server may be behind a token, and often should be -- a tailnet
        /// is not single-user. Read from the Keychain by the app, never stored here.
        public var bearerToken: String?

        /// Send OpenAI-style `response_format` with a JSON schema.
        ///
        /// Off by default, because the endpoint this exists to serve --
        /// `mlx_lm.server` -- does not support it, and sending it there is at best
        /// ignored. On for a hosted OpenAI-compatible endpoint that does, where it
        /// buys the same guarantee `output_config.format` buys on Anthropic.
        ///
        /// This is the axis the whole evaluation turns on, so it is a setting
        /// rather than an assumption: the same provider can be measured
        /// constrained and unconstrained against the same model.
        public var usesResponseFormat: Bool

        public init(baseURL: URL,
                    model: String = "local",
                    maxTokens: Int = 2048,
                    timeout: TimeInterval = 180,
                    bearerToken: String? = nil,
                    usesResponseFormat: Bool = false) {
            self.baseURL = baseURL
            self.model = model
            self.maxTokens = maxTokens
            self.timeout = timeout
            self.bearerToken = bearerToken
            self.usesResponseFormat = usesResponseFormat
        }
    }

    public typealias Observer = @Sendable (AnthropicProvider.Measurement) -> Void

    private let configuration: Configuration
    private let session: URLSession
    private let observe: Observer?

    /// One at a time. A single GPU serialises anyway, so four concurrent requests
    /// only means four requests each taking four times as long -- and on a Mac
    /// that might be asleep, a queue of four is four slots to lose.
    private let queue = RequestQueue(maxConcurrent: 1)

    public init(configuration: Configuration,
                session: URLSession = .shared,
                observe: Observer? = nil) {
        self.configuration = configuration
        self.session = session
        self.observe = observe
    }

    // MARK: - SolutionProvider

    public var identifier: String {
        let mode = configuration.usesResponseFormat ? "constrained" : "unconstrained"
        return "local/\(configuration.model)/\(mode)"
    }

    public var maxConcurrentRequests: Int { 1 }

    /// A URL is all it takes to be configured. Whether anything is *listening* is
    /// a question only a request can answer, and pretending otherwise would make
    /// a sleeping Mac look like a misconfiguration.
    public var isConfigured: Bool { true }

    /// `mlx_lm.server` is text-only, so photographs arrive as recognised text via
    /// `SightedProvider`. A server fronting a vision model could set this true.
    public var acceptsImageInput: Bool { false }

    // MARK: - Surfaces

    public func lesson(for problem: ProblemInput) async throws -> LessonContent {
        let raw = try await complete(AnthropicPrompts.lesson(problem),
                                    surface: "lesson", schema: .lesson)
        return try decode(LessonContent.self, from: raw, surface: "lesson")
    }

    public func steps(for problem: ProblemInput) async throws -> [StepItem] {
        let raw = try await complete(AnthropicPrompts.steps(problem),
                                    surface: "steps", schema: .steps)
        return try decodeList(StepItem.self, from: raw, surface: "steps")
    }

    public func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        let raw = try await complete(AnthropicPrompts.formulas(problem),
                                    surface: "formulas", schema: .formulas)
        return try decodeList(FormulaItem.self, from: raw, surface: "formulas")
    }

    public func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        let raw = try await complete(AnthropicPrompts.videos(problem),
                                    surface: "videos", schema: .videos)
        return try decodeList(VideoItem.self, from: raw, surface: "videos")
    }

    /// The array surfaces, which under a JSON schema arrive wrapped in an object
    /// because a bare array at the schema root is not reliably accepted. Falls
    /// back to a plain array, which is what an unconstrained model emits.
    private func decodeList<Element: Decodable>(_ element: Element.Type,
                                                from raw: String,
                                                surface: String) throws -> [Element] {
        if configuration.usesResponseFormat,
           let wrapped = LLMJSON.decode(ItemsWrapper<Element>.self, from: raw) {
            lastCompliance.set(wrapped.compliance)
            return wrapped.value.items
        }
        return try decode([Element].self, from: raw, surface: surface)
    }

    private struct ItemsWrapper<Element: Decodable>: Decodable {
        let items: [Element]
    }

    public func chatReply(to message: String,
                          about problem: String,
                          history: [ChatMessage]) async throws -> String {
        var messages: [[String: String]] = [
            ["role": "system", "content": AnthropicPrompts.chatSystem(problem)]
        ]
        messages += history.map { ["role": $0.role.rawValue, "content": $0.content] }
        messages.append(["role": "user", "content": message])
        return try await complete(messages: messages, surface: "chat").text
    }

    public func title(for problem: ProblemInput) async -> String {
        let fallback: String
        switch problem {
        case .text(let text): fallback = String(text.prefix(40))
        case .image: fallback = "Scanned Problem"
        }
        guard let raw = try? await complete(AnthropicPrompts.title(problem), surface: "title")
        else { return fallback }
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > 60 { return fallback }
        return title
    }

    // MARK: - Decoding
    //
    // Through the full repair ladder, because there is nothing constraining this
    // model's output. This is the backend the ladder exists for.

    private func decode<T: Decodable>(_ type: T.Type,
                                      from raw: String,
                                      surface: String) throws -> T {
        guard let decoded = LLMJSON.decode(type, from: raw) else {
            report(surface: surface, latency: 0, input: nil, output: nil,
                   compliance: nil, failure: "could not parse response")
            throw SolverError.decodingFailed(context: "\(surface): could not parse response")
        }
        lastCompliance.set(decoded.compliance)
        return decoded.value
    }

    /// Carries the compliance record from `decode` back to the reporting site,
    /// which measured the request and so owns the latency and the token counts.
    private let lastCompliance = ComplianceSlot()

    // MARK: - Networking

    private func complete(_ prompt: String,
                          surface: String,
                          schema: JSONSchema? = nil) async throws -> String {
        try await complete(messages: [["role": "user", "content": prompt]],
                           surface: surface, schema: schema).text
    }

    private struct Completion {
        let text: String
        let inputTokens: Int?
        let outputTokens: Int?
    }

    private func complete(messages: [[String: String]],
                          surface: String,
                          schema: JSONSchema? = nil) async throws -> Completion {
        try await queue.withSlot {
            let started = Date()
            let completion = try await self.perform(messages: messages, schema: schema)
            self.report(surface: surface,
                        latency: Date().timeIntervalSince(started),
                        input: completion.inputTokens,
                        output: completion.outputTokens,
                        compliance: self.lastCompliance.take(),
                        failure: nil)
            return completion
        }
    }

    private func perform(messages: [[String: String]],
                         schema: JSONSchema?) async throws -> Completion {
        var request = URLRequest(url: Self.completionsURL(configuration.baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token = configuration.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        request.timeoutInterval = configuration.timeout
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "max_tokens": configuration.maxTokens,
            // Deterministic, so a rerun of the evaluation means something. Some
            // endpoints pin sampling to their own defaults and ignore this; that
            // is their prerogative and it is why seeds are recorded per run.
            "temperature": 0,
            "stream": false,
        ]
        if configuration.usesResponseFormat, let schema {
            // The OpenAI spelling of the same idea as Anthropic's
            // `output_config.format`.
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": "solvr_response",
                                "strict": true,
                                "schema": schema.object],
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                // The common case by far, and worth its own sentence: the Mac is
                // asleep or the server is not running.
                throw SolverError.backendUnavailable(
                    reason: "Could not reach your local server at "
                          + "\(configuration.baseURL.host ?? "the configured address"). "
                          + "Is the Mac awake and the model serving?")
            case .timedOut:
                throw SolverError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw SolverError.networkUnavailable
            default:
                throw SolverError.apiError(urlError.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw SolverError.invalidResponse
        }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401, 403: throw SolverError.unauthorized
            case 429: throw SolverError.rateLimited(retryAfter: nil)
            case 500...599: throw SolverError.serverError(statusCode: http.statusCode)
            default: throw SolverError.apiError("Status \(http.statusCode)")
            }
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let choice = (root?["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]

        // A reasoning model served this way splits its answer in two: `content`
        // arrives null or empty and the text is under `reasoning_content`. Reading
        // only `content` gets an empty response and blames the model.
        let content = (message?["content"] as? String) ?? ""
        let reasoning = (message?["reasoning_content"] as? String)
            ?? (message?["reasoning"] as? String) ?? ""
        let text = content.isEmpty ? reasoning : content

        guard !text.isEmpty else { throw SolverError.emptyResponse }

        let usage = root?["usage"] as? [String: Any]
        return Completion(text: text,
                          inputTokens: usage?["prompt_tokens"] as? Int,
                          outputTokens: usage?["completion_tokens"] as? Int)
    }

    /// Tolerate a base URL given with or without the `/v1` suffix.
    ///
    /// Both spellings are in the wild -- `mlx_lm.server` is documented as a bare
    /// host and port, Moonshot documents `https://api.moonshot.ai/v1` -- and
    /// blindly appending produces `/v1/v1/chat/completions`, which 404s in a way
    /// that looks like the server is down.
    static func completionsURL(_ base: URL) -> URL {
        var path = base.path
        while path.hasSuffix("/") { path.removeLast() }
        let suffix = path.hasSuffix("/v1") ? "chat/completions" : "v1/chat/completions"
        return base.appendingPathComponent(suffix)
    }

    private func report(surface: String, latency: TimeInterval,
                        input: Int?, output: Int?,
                        compliance: LLMJSON.Compliance?, failure: String?) {
        observe?(AnthropicProvider.Measurement(
            surface: surface, backend: identifier, latency: latency,
            inputTokens: input, outputTokens: output,
            compliance: compliance, failure: failure))
    }
}

/// A one-slot mailbox. `decode` learns the compliance record but does not know the
/// latency; the request site knows the latency but not the compliance. This hands
/// one to the other without threading a parameter through every surface.
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
