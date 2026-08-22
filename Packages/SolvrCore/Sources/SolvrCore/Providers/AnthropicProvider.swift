import Foundation

/// Solvr against the Anthropic Messages API.
///
/// This is the quality ceiling every other backend is measured against, and the
/// only one that reads a photograph natively rather than through text
/// recognition.
///
/// It lives in `SolvrCore`, not the app, for one reason: the evaluation harness
/// has to measure *the code the app actually runs*. A harness with its own HTTP
/// client would be measuring a second implementation and reporting the numbers as
/// if they came from the first. Everything the app used to supply directly --
/// the key, the network check, the image -- is injected or passed as bytes, so
/// nothing here needs UIKit and all of it is reachable from `swift run`.
public final class AnthropicProvider: SolutionProvider {

    public struct Configuration: Sendable {
        public var model: String
        public var maxTokens: Int

        /// Ask the API to guarantee the response shape rather than asking the
        /// prompt to.
        ///
        /// This is the variable the whole evaluation turns on. With it off, the
        /// model is told "Return ONLY valid JSON" and we clean up afterwards;
        /// with it on, `output_config.format` constrains decoding and the
        /// response is valid JSON by construction. The prompt is deliberately
        /// left *identical* between the two so the only thing that differs is the
        /// decoding mechanism -- a real implementation would also delete the now
        /// redundant schema from the prompt, but then two things would have
        /// changed and the comparison would mean less.
        public var usesStructuredOutputs: Bool

        public var timeout: TimeInterval

        public init(model: String = "claude-opus-5",
                    maxTokens: Int = 2048,
                    usesStructuredOutputs: Bool = false,
                    timeout: TimeInterval = 90) {
            self.model = model
            self.maxTokens = maxTokens
            self.usesStructuredOutputs = usesStructuredOutputs
            self.timeout = timeout
        }
    }

    /// What one request cost and what had to be done to its answer. The app
    /// ignores this; the harness is built on it.
    public struct Measurement: Sendable {
        public let surface: String
        public let backend: String
        public let latency: TimeInterval
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let compliance: LLMJSON.Compliance?
        public let failure: String?
    }

    public typealias Observer = @Sendable (Measurement) -> Void

    private let configuration: Configuration
    private let apiKey: @Sendable () -> String?
    private let isOnline: @Sendable () -> Bool
    private let observe: Observer?
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Four at once suits a hosted API's rate limits. It is a property of this
    /// backend rather than a constant of the app: an on-device session throws if
    /// asked two things at a time.
    private let requestQueue = RequestQueue(maxConcurrent: 4)

    public init(configuration: Configuration = Configuration(),
                apiKey: @escaping @Sendable () -> String?,
                isOnline: @escaping @Sendable () -> Bool = { true },
                session: URLSession = .shared,
                observe: Observer? = nil) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.isOnline = isOnline
        self.session = session
        self.observe = observe
    }

    // MARK: - SolutionProvider

    public var identifier: String {
        let mode = configuration.usesStructuredOutputs ? "constrained" : "unconstrained"
        return "anthropic/\(configuration.model)/\(mode)"
    }

    public var maxConcurrentRequests: Int { 4 }

    public var isConfigured: Bool {
        guard let key = apiKey() else { return false }
        return !key.isEmpty
    }

    /// The one backend that genuinely sees the picture.
    public var acceptsImageInput: Bool { true }

    // MARK: - The four surfaces

    public func lesson(for problem: ProblemInput) async throws -> LessonContent {
        try await fetch(LessonContent.self,
                        surface: "lesson",
                        prompt: AnthropicPrompts.lesson(problem),
                        problem: problem,
                        schema: .lesson)
    }

    public func steps(for problem: ProblemInput) async throws -> [StepItem] {
        try await fetchList(StepItem.self,
                            surface: "steps",
                            prompt: AnthropicPrompts.steps(problem),
                            problem: problem,
                            schema: .steps)
    }

    public func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        try await fetchList(FormulaItem.self,
                            surface: "formulas",
                            prompt: AnthropicPrompts.formulas(problem),
                            problem: problem,
                            schema: .formulas)
    }

    public func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        try await fetchList(VideoItem.self,
                            surface: "videos",
                            prompt: AnthropicPrompts.videos(problem),
                            problem: problem,
                            schema: .videos)
    }

    public func chatReply(to message: String,
                          about problem: String,
                          history: [ChatMessage]) async throws -> String {
        let turns = history.map { (role: $0.role.rawValue, content: $0.content) }
        let (text, _) = try await send(prompt: message,
                                       imageJPEG: nil,
                                       system: AnthropicPrompts.chatSystem(problem),
                                       history: turns,
                                       schema: nil,
                                       surface: "chat")
        return text
    }

    public func title(for problem: ProblemInput) async -> String {
        let fallback: String
        switch problem {
        case .text(let text): fallback = String(text.prefix(40))
        case .image: fallback = "Scanned Problem"
        }
        guard let (text, _) = try? await send(prompt: AnthropicPrompts.title(problem),
                                              imageJPEG: problem.imageJPEG,
                                              system: nil,
                                              history: [],
                                              schema: nil,
                                              surface: "title")
        else { return fallback }

        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title.count <= 60 { return title }
        let words = title.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? fallback : words
    }

    // MARK: - Problem detection
    //
    // Not part of `SolutionProvider`: nothing in the shipping UI reaches it --
    // `HomeView` inlines its own camera flow and `ScannerViewModel` is
    // unreferenced -- so putting it in the protocol would oblige every future
    // backend to implement a feature the app does not use. It also depends on
    // native vision, which the on-device backend does not have.

    public func detectProblems(inImageJPEG data: Data) async throws -> [DetectedProblem] {
        let prompt = """
        You are analyzing a photo taken of a computer screen displaying a math document (PDF, webpage, or document viewer).

        IMPORTANT CONTEXT: This is a PHOTO OF A SCREEN, not a direct scan. The image contains:
        - Browser/app UI elements (toolbars, tabs, buttons, sidebars) — IGNORE ALL OF THESE
        - Document viewer controls (page numbers, zoom, scroll bars) — IGNORE ALL OF THESE
        - Desktop elements (dock, taskbar, other windows, notifications) — IGNORE ALL OF THESE
        - The actual document content area — THIS IS WHERE THE MATH PROBLEMS ARE

        Your job: Find ONLY the actual numbered math problems/equations within the document content area.

        For each math problem found:
        1. Bounding box as PRECISE percentage coordinates (use decimals like 45.3, not just 45):
           - top: distance from top of image (0.0 = top edge, 100.0 = bottom edge)
           - left: distance from left of image (0.0 = left edge, 100.0 = right edge)
           - width: width as percentage of image width
           - height: height as percentage of image height
           - The box must TIGHTLY wrap just that one problem with ~1% padding

        2. The complete math problem translated into LaTeX:
           - English text portions wrapped in \\text{}: e.g. \\text{Consider the integral }
           - All math in proper LaTeX: \\int_0^{\\sqrt{2}}, \\frac{d}{dx}, \\sqrt{x^2+y^2}
           - Include the FULL problem statement

        RULES:
        - ONLY detect numbered math problems like (1), (2), (3)... or 1., 2., 3... within the actual document
        - Each problem number = one detection. Do NOT merge multiple problems into one box.
        - Do NOT detect: file names, page numbers, zoom controls, buttons, headers, footers, browser UI
        - Maximum 10 problems per image

        Return ONLY valid JSON array, no other text:
        [{"bbox":{"top":52.1,"left":4.2,"width":85.3,"height":3.8},"latex":"\\text{(3) ...}"}]
        """

        let (raw, _) = try await send(prompt: prompt, imageJPEG: data, system: nil,
                                      history: [], schema: nil, surface: "detection")
        guard let decoded = LLMJSON.decode([DetectedProblem].self, from: raw) else {
            throw SolverError.decodingFailed(context: "problem detection")
        }
        return decoded.value
    }

    // MARK: - Decoding

    private func fetch<T: Decodable>(_ type: T.Type,
                                     surface: String,
                                     prompt: String,
                                     problem: ProblemInput,
                                     schema: JSONSchema) async throws -> T {
        let (raw, metrics) = try await send(prompt: prompt,
                                            imageJPEG: problem.imageJPEG,
                                            system: nil,
                                            history: [],
                                            schema: configuration.usesStructuredOutputs ? schema : nil,
                                            surface: surface,
                                            reportImmediately: false)
        guard let decoded = LLMJSON.decode(type, from: raw) else {
            report(surface: surface, metrics: metrics, compliance: nil,
                   failure: "could not parse response")
            throw SolverError.decodingFailed(context: "\(surface): could not parse response")
        }
        report(surface: surface, metrics: metrics, compliance: decoded.compliance, failure: nil)
        return decoded.value
    }

    /// The array surfaces, which under structured outputs arrive wrapped in an
    /// object because a bare array at the schema root is not reliably accepted.
    private func fetchList<Element: Decodable>(_ element: Element.Type,
                                               surface: String,
                                               prompt: String,
                                               problem: ProblemInput,
                                               schema: JSONSchema) async throws -> [Element] {
        let (raw, metrics) = try await send(prompt: prompt,
                                            imageJPEG: problem.imageJPEG,
                                            system: nil,
                                            history: [],
                                            schema: configuration.usesStructuredOutputs ? schema : nil,
                                            surface: surface,
                                            reportImmediately: false)

        if configuration.usesStructuredOutputs,
           let wrapped = LLMJSON.decode(Wrapper<Element>.self, from: raw) {
            report(surface: surface, metrics: metrics,
                   compliance: wrapped.compliance, failure: nil)
            return wrapped.value.items
        }

        if let decoded = LLMJSON.decode([Element].self, from: raw) {
            report(surface: surface, metrics: metrics,
                   compliance: decoded.compliance, failure: nil)
            return decoded.value
        }

        report(surface: surface, metrics: metrics, compliance: nil,
               failure: "could not parse response")
        throw SolverError.decodingFailed(context: "\(surface): could not parse response")
    }

    private struct Wrapper<Element: Decodable>: Decodable {
        let items: [Element]
    }

    private func report(surface: String,
                        metrics: (latency: TimeInterval, input: Int?, output: Int?),
                        compliance: LLMJSON.Compliance?,
                        failure: String?) {
        observe?(Measurement(surface: surface,
                             backend: identifier,
                             latency: metrics.latency,
                             inputTokens: metrics.input,
                             outputTokens: metrics.output,
                             compliance: compliance,
                             failure: failure))
    }

    // MARK: - Networking

    private func send(prompt: String,
                      imageJPEG: Data?,
                      system: String?,
                      history: [(role: String, content: String)],
                      schema: JSONSchema?,
                      surface: String,
                      reportImmediately: Bool = true)
    async throws -> (String, (latency: TimeInterval, input: Int?, output: Int?)) {
        // One release on every path, including cancellation. An earlier version
        // released at five separate call sites; a slot missed at any of them was
        // gone for the life of the process, and after four the app stopped making
        // requests with nothing on screen to say why.
        try await requestQueue.withSlot {
            do {
                return try await self.perform(prompt: prompt, imageJPEG: imageJPEG,
                                              system: system, history: history,
                                              schema: schema, surface: surface,
                                              reportImmediately: reportImmediately)
            } catch let error as SolverError {
                guard case .rateLimited(let retryAfter) = error else { throw error }
                // Cancellation propagates rather than being swallowed by `try?`:
                // a user who has left the screen should stop the retry.
                try await Task.sleep(for: .seconds(retryAfter ?? 5.0))
                return try await self.perform(prompt: prompt, imageJPEG: imageJPEG,
                                              system: system, history: history,
                                              schema: schema, surface: surface,
                                              reportImmediately: reportImmediately)
            }
        }
    }

    private func perform(prompt: String,
                         imageJPEG: Data?,
                         system: String?,
                         history: [(role: String, content: String)],
                         schema: JSONSchema?,
                         surface: String,
                         reportImmediately: Bool)
    async throws -> (String, (latency: TimeInterval, input: Int?, output: Int?)) {
        guard isOnline() else { throw SolverError.networkUnavailable }
        guard let key = apiKey(), !key.isEmpty else { throw SolverError.noAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = configuration.timeout
        request.httpBody = try AnthropicWire.requestBody(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            prompt: prompt,
            imageJPEG: imageJPEG,
            system: system,
            history: history,
            schema: schema)

        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw SolverError.networkUnavailable
            case .timedOut:
                throw SolverError.timeout
            default:
                throw SolverError.apiError(urlError.localizedDescription)
            }
        }
        let latency = Date().timeIntervalSince(started)

        guard let http = response as? HTTPURLResponse else {
            throw SolverError.invalidResponse
        }

        let parsed = AnthropicWire.Response(data: data)

        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401:
                throw SolverError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap { TimeInterval($0) }
                throw SolverError.rateLimited(retryAfter: retryAfter)
            case 500...599:
                throw SolverError.serverError(statusCode: http.statusCode)
            default:
                throw SolverError.apiError(parsed.errorMessage ?? "Status \(http.statusCode)")
            }
        }

        guard let text = parsed.text else { throw SolverError.emptyResponse }

        let metrics = (latency: latency, input: parsed.inputTokens, output: parsed.outputTokens)
        if reportImmediately {
            report(surface: surface, metrics: metrics, compliance: nil, failure: nil)
        }
        return (text, metrics)
    }
}

private extension ProblemInput {
    var imageJPEG: Data? {
        if case .image(let data) = self { return data }
        return nil
    }
}
