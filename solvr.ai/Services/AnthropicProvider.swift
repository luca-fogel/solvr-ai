import Foundation
import UIKit
import SolvrCore

/// Solvr against the Anthropic Messages API.
///
/// This is the quality ceiling every other backend is measured against, and it
/// is the only one that reads a photograph natively rather than through text
/// recognition.
///
/// It used to be `ClaudeAPIManager`, a singleton that also owned the app's
/// loading flags and short-circuited to demo fixtures at the top of all twelve
/// of its methods. Both of those now live outside it: loading state belongs to
/// the screen showing it, and the demo path is a provider of its own. What is
/// left is what is genuinely Anthropic-specific -- the prompts, the wire format
/// and the decode ladder.
final class AnthropicProvider: SolutionProvider {

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Normalises whatever is in `UserDefaults` onto a model ID that exists.
    ///
    /// The old mapping sent Haiku to `claude-haiku-4-5-20251001`; current IDs
    /// carry no date suffix, so that string is not a model. Note the `default`
    /// branch passes unrecognised values straight through -- a previous version
    /// rewrote them to Sonnet, which would silently discard a local model name
    /// stored under the same key.
    private var selectedModel: String {
        let stored = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        switch stored {
        case "", "claude-sonnet-4-20250514":
            return "claude-opus-5"
        case "claude-haiku-4-20250414", "claude-haiku-4-5-20251001":
            return "claude-haiku-4-5"
        default:
            return stored
        }
    }

    private var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxTokens")
        return stored > 0 ? stored : 2048
    }

    private var apiKey: String? {
        KeychainManager.retrieve()
    }

    /// Four at once suits a hosted API's rate limits. It is a property of this
    /// backend rather than a constant of the app, because an on-device session
    /// throws if you ask it two things at a time.
    private let requestQueue = RequestQueue(maxConcurrent: 4)

    // MARK: - SolutionProvider

    var identifier: String { "anthropic/\(selectedModel)" }
    var maxConcurrentRequests: Int { 4 }
    var isConfigured: Bool { KeychainManager.hasAPIKey }

    /// The one backend that genuinely sees the picture.
    var acceptsImageInput: Bool { true }

    // MARK: - Prompts
    //
    // The prompts live here rather than in the app because they are a property
    // of the backend: a 4B needs shorter, more constrained instructions than
    // Opus, and a backend with guided generation needs no schema in the prompt
    // at all. Each is written once and told how to refer to the problem, which
    // is the only thing that differed between the old text and image variants.

    private func problemClause(_ input: ProblemInput) -> String {
        switch input {
        case .text(let problem):
            return "The student submitted this problem: '\(problem)'."
        case .image:
            return "Look at the math problem in this image."
        }
    }

    private func lessonPrompt(_ input: ProblemInput) -> String {
        """
        You are a world-class math tutor. \(problemClause(input))

        Teach the underlying math concept (do NOT solve the exact problem).

        Return ONLY valid JSON with this structure:
        {
            "title": "Concept Name",
            "topic": "CATEGORY \u{2022} SUBCATEGORY",
            "introduction": "1-2 sentences explaining when/why this concept matters.",
            "sections": [
                {
                    "heading": "Section Title",
                    "content": "Explanation text. Use $...$ for inline LaTeX math.",
                    "formula": "LaTeX expression for key formula (optional, null if none)",
                    "note": "Brief clarification (optional, null if none)",
                    "steps": ["Step 1 text", "Step 2 text"]
                }
            ],
            "keyTakeaway": "1-2 sentence summary of the key idea."
        }

        Rules:
        - Use LaTeX for ALL math expressions inside $...$ delimiters
        - "content" is plain text with optional $inline math$
        - "formula" is pure LaTeX (no $ delimiters, no text)
        - Include 3-5 sections covering: the concept, intuition/analogy, and a worked example
        - "steps" is optional (null if not a worked example section)
        - Return ONLY the JSON, no markdown fences, no explanation
        """
    }

    private func formulasPrompt(_ input: ProblemInput) -> String {
        """
        \(problemClause(input)) List 3-6 key mathematical formulas relevant to it.

        Return ONLY a valid JSON array with this structure:
        [{"name": "Formula Name", "formula": "\\\\frac{a}{b}", "description": "When and how to use this formula"}]

        Rules:
        - "formula" must be valid LaTeX. CRITICAL: In JSON, all backslashes must be doubled — write \\\\frac{}{} not \\frac{}{}, \\\\sqrt{} not \\sqrt{}, \\\\pi not \\pi
        - "description" is plain text, 1-2 sentences
        - "name" is a short human-readable label
        - Return ONLY the JSON array, no other text, no markdown fences
        """
    }

    private func stepsPrompt(_ input: ProblemInput) -> String {
        """
        \(problemClause(input)) Solve it step by step.

        Return ONLY a valid JSON array with this structure:
        [{"step": 1, "title": "Short action title", "explanation": "Plain text explanation of what we're doing", "math": "\\\\frac{x}{y}"}]

        Rules:
        - "step" is the step number (integer, starting at 1)
        - "title" is a short action phrase like "Identify the equation" or "Factor the expression"
        - "explanation" is 1-2 sentences in plain text describing the reasoning. Do NOT use LaTeX in explanations — use words like "x squared" or "the integral of f(x)".
        - "math" is the LaTeX expression showing the algebraic work. CRITICAL: In JSON, all backslashes must be doubled. Write \\\\frac not \\frac, \\\\sqrt not \\sqrt, \\\\int not \\int, \\\\pi not \\pi. Every LaTeX backslash must be \\\\ in the JSON string.
        - "math" can be null if the step is purely conceptual
        - The LAST step should contain the final answer
        - Show every algebraic step clearly
        - Return ONLY the JSON array, no other text, no markdown fences
        """
    }

    private func videosPrompt(_ input: ProblemInput) -> String {
        """
        \(problemClause(input)) \
        Suggest 4-5 specific YouTube educational videos for learning about this math topic. \
        Include videos from channels like Khan Academy, 3Blue1Brown, Professor Leonard, \
        Organic Chemistry Tutor, PatrickJMT. For each, provide: title, channel name, a specific YouTube search query, \
        and if you know the exact YouTube video ID include it as "videoId". \
        Make search queries very specific, including the exact math concept and operation. \
        Format as JSON array: [{"title": "...", "channel": "...", "searchQuery": "...", "videoId": "...", "thumbnailURL": ""}]. \
        Return ONLY valid JSON.
        """
    }

    // MARK: - The four surfaces

    func lesson(for problem: ProblemInput) async throws -> LessonContent {
        let response = try await respond(to: lessonPrompt(problem), about: problem)
        let body = LLMJSON.sliceJSONBody(response, shape: .object)
        guard let decoded = LLMJSON.decode(LessonContent.self, from: body) else {
            throw SolverError.decodingFailed(context: "lesson: could not parse response")
        }
        if decoded.provenance != .strict {
            print("[anthropic] lesson parsed via \(decoded.provenance.rawValue)")
        }
        return decoded.value
    }

    func steps(for problem: ProblemInput) async throws -> [StepItem] {
        let response = try await respond(to: stepsPrompt(problem), about: problem)
        return try decodeJSON([StepItem].self, from: response, context: "steps")
    }

    func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        let response = try await respond(to: formulasPrompt(problem), about: problem)
        return try decodeJSON([FormulaItem].self, from: response, context: "formulas")
    }

    func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        let response = try await respond(to: videosPrompt(problem), about: problem)
        return try decodeJSON([VideoItem].self, from: response, context: "videos")
    }

    // MARK: - Chat

    func chatReply(to message: String,
                   about problem: String,
                   history: [ChatMessage]) async throws -> String {
        let systemPrompt = """
        You are a friendly, patient math tutor. The student is working on this problem: '\(problem)'. \
        They've already seen the lesson and step-by-step solution. \
        Answer their follow-up questions clearly and encouragingly. Use simple language. \
        If they're confused, try explaining differently with an analogy.
        """

        var messages: [ClaudeMessage] = history.map {
            ClaudeMessage(role: $0.role.rawValue, content: $0.content)
        }
        messages.append(ClaudeMessage(role: "user", content: message))
        return try await sendMessages(messages, system: systemPrompt)
    }

    // MARK: - Title

    func title(for problem: ProblemInput) async -> String {
        let fallback: String
        switch problem {
        case .text(let text): fallback = String(text.prefix(40))
        case .image: fallback = "Scanned Problem"
        }

        let prompt = """
        \(problemClause(problem))

        Respond with ONLY a 3-5 word title summarizing what the problem is about. Examples: "Surface Area Integral", "Curl of Vector Field", "Quadratic Factoring", "Taylor Series Expansion", "Double Integral Polar".

        Respond with ONLY the short title, nothing else. No quotes, no period, no explanation.
        """

        guard let response = try? await respond(to: prompt, about: problem) else {
            return fallback
        }
        let title = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title.count <= 60 { return title }
        let words = title.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? fallback : words
    }

    // MARK: - Problem detection
    //
    // Not part of `SolutionProvider`: nothing in the shipping UI reaches it --
    // `HomeView` inlines its own camera flow and `ScannerViewModel` is
    // unreferenced -- so putting it in the protocol would oblige every future
    // backend to implement a feature the app does not use.

    func detectProblems(in image: UIImage) async throws -> [DetectedProblem] {
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

        let response = try await sendImageMessage(image, prompt: prompt)
        let extracted = response.extractJSONArray()
        do {
            return try JSONDecoder().decode([DetectedProblem].self, from: Data(extracted.utf8))
        } catch {
            throw SolverError.decodingFailed(context: "problem detection")
        }
    }

    // MARK: - Dispatch

    /// One place that decides whether a prompt travels as text or alongside an
    /// image, so every surface above stays free of that branch.
    private func respond(to prompt: String, about problem: ProblemInput) async throws -> String {
        switch problem {
        case .text:
            return try await sendMessages([ClaudeMessage(role: "user", content: prompt)])
        case .image(let data):
            guard let image = UIImage(data: data) else {
                throw SolverError.invalidResponse
            }
            return try await sendImageMessage(image, prompt: prompt)
        }
    }

    // MARK: - Image Utilities

    private func imageBase64(_ image: UIImage) -> String? {
        image.jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }

    // MARK: - Image Message Networking

    private func sendImageMessage(_ image: UIImage, prompt: String) async throws -> String {
        await requestQueue.acquire()
        do {
            let result = try await performImageRequest(image, prompt: prompt)
            await requestQueue.release()
            return result
        } catch let error as SolverError {
            if case .rateLimited(let retryAfter) = error {
                let delay = retryAfter ?? 5.0
                try? await Task.sleep(for: .seconds(delay))
                do {
                    let result = try await performImageRequest(image, prompt: prompt)
                    await requestQueue.release()
                    return result
                } catch {
                    await requestQueue.release()
                    throw error
                }
            }
            await requestQueue.release()
            throw error
        } catch {
            await requestQueue.release()
            throw error
        }
    }

    private func performImageRequest(_ image: UIImage, prompt: String) async throws -> String {
        guard NetworkMonitor.shared.isConnected else {
            throw SolverError.networkUnavailable
        }
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw SolverError.noAPIKey
        }
        guard let base64 = imageBase64(image) else {
            throw SolverError.invalidResponse
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 90

        let body = ClaudeMultiModalRequest(
            model: selectedModel,
            max_tokens: maxTokens,
            messages: [
                .init(role: "user", content: [
                    .init(imageData: base64),
                    .init(text: prompt),
                ])
            ],
            system: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let httpResponse: URLResponse
        do {
            (data, httpResponse) = try await URLSession.shared.data(for: request)
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

        guard let http = httpResponse as? HTTPURLResponse else {
            throw SolverError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "no body"
            print("[ClaudeAPI] Image HTTP \(http.statusCode): \(bodyString)")

            switch http.statusCode {
            case 401: throw SolverError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap { TimeInterval($0) }
                throw SolverError.rateLimited(retryAfter: retryAfter)
            case 500...599: throw SolverError.serverError(statusCode: http.statusCode)
            default:
                let apiResponse = try? JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
                let msg = apiResponse?.error?.message ?? "Status \(http.statusCode)"
                throw SolverError.apiError(msg)
            }
        }

        let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = apiResponse.text else {
            throw SolverError.emptyResponse
        }
        return text
    }

    // MARK: - JSON Decoding Helper

    private func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String, context: String) throws -> T {
        let body = LLMJSON.sliceJSONBody(raw, shape: .array)

        if let decoded = LLMJSON.decode(type, from: body) {
            if decoded.provenance != .strict {
                print("[ClaudeAPI] \(context) parsed via \(decoded.provenance.rawValue)")
            }
            return decoded.value
        }

        // Last resort: the model answered in prose. Show what it said rather
        // than an error, wrapped in the shape this tab expects.
        if let fallback = wrapPlainTextFallback(LLMJSON.stripCodeFences(raw),
                                                context: context, type: type) {
            print("[ClaudeAPI] used plain text fallback for \(context)")
            return fallback
        }

        throw SolverError.decodingFailed(context: "\(context): could not parse response")
    }

    private func wrapPlainTextFallback<T: Decodable>(_ text: String, context: String, type: T.Type) -> T? {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let json: String
        switch context {
        case "steps":
            json = """
            [{"step":1,"title":"Solution","explanation":"\(escaped)","math":null}]
            """
        case "formulas":
            json = """
            [{"name":"Result","formula":"","description":"\(escaped)"}]
            """
        case "videos":
            json = """
            [{"title":"Search for this topic","channel":"YouTube","searchQuery":"\(escaped)","videoId":"","thumbnailURL":""}]
            """
        default:
            return nil
        }

        let data = Data(json.utf8)
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Core Networking

    private func sendMessages(_ messages: [ClaudeMessage], system: String? = nil) async throws -> String {
        // One release, on every path, including cancellation. The previous
        // version released at five separate call sites; a slot missed at any of
        // them is gone for the life of the process, and after four the app stops
        // making requests with nothing on screen to say why.
        try await requestQueue.withSlot {
            do {
                return try await self.performRequest(messages, system: system)
            } catch let error as SolverError {
                guard case .rateLimited(let retryAfter) = error else { throw error }
                // Cancellation propagates here rather than being swallowed by
                // `try?`: a user who has left the screen should stop the retry.
                try await Task.sleep(for: .seconds(retryAfter ?? 5.0))
                return try await self.performRequest(messages, system: system)
            }
        }
    }

    private func performRequest(_ messages: [ClaudeMessage], system: String? = nil) async throws -> String {
        guard NetworkMonitor.shared.isConnected else {
            throw SolverError.networkUnavailable
        }

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw SolverError.noAPIKey
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body = ClaudeRequest(model: selectedModel, maxTokens: maxTokens, messages: messages, system: system)
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let httpResponse: URLResponse
        do {
            (data, httpResponse) = try await URLSession.shared.data(for: request)
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

        guard let http = httpResponse as? HTTPURLResponse else {
            throw SolverError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "no body"
            print("[ClaudeAPI] HTTP \(http.statusCode): \(bodyString)")

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
                let apiResponse = try? JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
                let msg = apiResponse?.error?.message ?? "Status \(http.statusCode)"
                throw SolverError.apiError(msg)
            }
        }

        let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)

        guard let text = apiResponse.text else {
            throw SolverError.emptyResponse
        }

        return text
    }
}
