import Foundation
import UIKit
import SolvrCore

@Observable
final class ClaudeAPIManager {

    static let shared = ClaudeAPIManager()

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    private var selectedModel: String {
        let stored = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        switch stored {
        case "claude-sonnet-4-20250514":
            return "claude-sonnet-4-6"
        case "claude-haiku-4-20250414":
            return "claude-haiku-4-5-20251001"
        case "":
            return "claude-sonnet-4-6"
        default:
            return stored
        }
    }

    private var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxTokens")
        return stored > 0 ? stored : 2048
    }

    var isLoadingLesson = false
    var isLoadingFormulas = false
    var isLoadingSteps = false
    var isLoadingVideos = false
    var isLoadingChat = false

    private var apiKey: String? {
        KeychainManager.retrieve()
    }

    private let requestQueue = RequestQueue(maxConcurrent: 4)

    private init() {}

    // MARK: - Lesson (JSON)

    func fetchLesson(for problem: String) async throws -> LessonContent {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode(LessonContent.self, from: DemoFixtures.lesson, label: "lesson")
        }
        isLoadingLesson = true
        defer { isLoadingLesson = false }

        let prompt = """
        You are a world-class math tutor. The student submitted this problem: '\(problem)'.

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

        let response = try await sendMessage(prompt)
        return try decodeLessonJSON(from: response)
    }

    func fetchLessonFromImage(_ image: UIImage) async throws -> LessonContent {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode(LessonContent.self, from: DemoFixtures.lesson, label: "lesson")
        }
        isLoadingLesson = true
        defer { isLoadingLesson = false }

        let prompt = """
        You are a world-class math tutor. Look at the math problem in this image.

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

        let response = try await sendImageMessage(image, prompt: prompt)
        return try decodeLessonJSON(from: response)
    }

    private func decodeLessonJSON(from raw: String) throws -> LessonContent {
        let body = LLMJSON.sliceJSONBody(raw, shape: .object)
        guard let decoded = LLMJSON.decode(LessonContent.self, from: body) else {
            throw ClaudeError.decodingFailed(context: "lesson: could not parse response")
        }
        if decoded.provenance != .strict {
            // Worth logging: a lesson that needed rescuing is a prompt problem,
            // and the prompt is the thing to fix.
            print("[ClaudeAPI] lesson parsed via \(decoded.provenance.rawValue)")
        }
        return decoded.value
    }

    // MARK: - Formulas (JSON)

    func fetchFormulas(for problem: String) async throws -> [FormulaItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([FormulaItem].self, from: DemoFixtures.formulas, label: "formulas")
        }
        isLoadingFormulas = true
        defer { isLoadingFormulas = false }

        let prompt = """
        List 3-6 key mathematical formulas relevant to this problem: '\(problem)'.

        Return ONLY a valid JSON array with this structure:
        [{"name": "Formula Name", "formula": "\\\\frac{a}{b}", "description": "When and how to use this formula"}]

        Rules:
        - "formula" must be valid LaTeX. CRITICAL: In JSON, all backslashes must be doubled — write \\\\frac{}{} not \\frac{}{}, \\\\sqrt{} not \\sqrt{}, \\\\pi not \\pi
        - "description" is plain text, 1-2 sentences
        - "name" is a short human-readable label
        - Return ONLY the JSON array, no other text, no markdown fences
        """

        let response = try await sendMessage(prompt)
        return try decodeJSON([FormulaItem].self, from: response, context: "formulas")
    }

    func fetchFormulasFromImage(_ image: UIImage) async throws -> [FormulaItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([FormulaItem].self, from: DemoFixtures.formulas, label: "formulas")
        }
        isLoadingFormulas = true
        defer { isLoadingFormulas = false }

        let prompt = """
        Look at the math problem in this image. List 3-6 key mathematical formulas relevant to it.

        Return ONLY a valid JSON array with this structure:
        [{"name": "Formula Name", "formula": "\\\\frac{a}{b}", "description": "When and how to use this formula"}]

        Rules:
        - "formula" must be valid LaTeX. CRITICAL: In JSON, all backslashes must be doubled — write \\\\frac{}{} not \\frac{}{}, \\\\sqrt{} not \\sqrt{}, \\\\pi not \\pi
        - "description" is plain text, 1-2 sentences
        - "name" is a short human-readable label
        - Return ONLY the JSON array, no other text, no markdown fences
        """

        let response = try await sendImageMessage(image, prompt: prompt)
        return try decodeJSON([FormulaItem].self, from: response, context: "formulas")
    }

    // MARK: - Step-by-Step (JSON)

    func fetchSteps(for problem: String) async throws -> [StepItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([StepItem].self, from: DemoFixtures.steps, label: "steps")
        }
        isLoadingSteps = true
        defer { isLoadingSteps = false }

        let prompt = """
        Solve this math problem step by step: '\(problem)'.

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

        let response = try await sendMessage(prompt)
        return try decodeJSON([StepItem].self, from: response, context: "steps")
    }

    func fetchStepsFromImage(_ image: UIImage) async throws -> [StepItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([StepItem].self, from: DemoFixtures.steps, label: "steps")
        }
        isLoadingSteps = true
        defer { isLoadingSteps = false }

        let prompt = """
        Look at the math problem in this image. Solve it step by step.

        Return ONLY a valid JSON array with this structure:
        [{"step": 1, "title": "Short action title", "explanation": "Plain text explanation", "math": "\\\\frac{x}{y}"}]

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

        let response = try await sendImageMessage(image, prompt: prompt)
        return try decodeJSON([StepItem].self, from: response, context: "steps")
    }

    // MARK: - Videos

    func fetchVideos(for problem: String) async throws -> [VideoItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([VideoItem].self, from: DemoFixtures.videos, label: "videos")
        }
        isLoadingVideos = true
        defer { isLoadingVideos = false }

        let prompt = """
        Suggest 4-5 specific YouTube educational videos for learning about this math topic: '\(problem)'. \
        Include videos from channels like Khan Academy, 3Blue1Brown, Professor Leonard, \
        Organic Chemistry Tutor, PatrickJMT. For each, provide: title, channel name, a specific YouTube search query, \
        and if you know the exact YouTube video ID include it as "videoId". \
        Make search queries very specific, including the exact math concept and operation. \
        Format as JSON array: [{"title": "...", "channel": "...", "searchQuery": "...", "videoId": "...", "thumbnailURL": ""}]. \
        Return ONLY valid JSON.
        """

        let response = try await sendMessage(prompt)
        return try decodeJSON([VideoItem].self, from: response, context: "videos")
    }

    func fetchVideosFromImage(_ image: UIImage) async throws -> [VideoItem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([VideoItem].self, from: DemoFixtures.videos, label: "videos")
        }
        isLoadingVideos = true
        defer { isLoadingVideos = false }

        let prompt = """
        Look at the math problem in this image. \
        Suggest 4-5 specific YouTube educational videos for learning about this math topic. \
        Include videos from channels like Khan Academy, 3Blue1Brown, Professor Leonard, \
        Organic Chemistry Tutor, PatrickJMT. For each, provide: title, channel name, a specific YouTube search query, \
        and if you know the exact YouTube video ID include it as "videoId". \
        Make search queries very specific, including the exact math concept and operation. \
        Format as JSON array: [{"title": "...", "channel": "...", "searchQuery": "...", "videoId": "...", "thumbnailURL": ""}]. \
        Return ONLY valid JSON.
        """

        let response = try await sendImageMessage(image, prompt: prompt)
        return try decodeJSON([VideoItem].self, from: response, context: "videos")
    }

    // MARK: - Chat

    func sendChatMessage(_ message: String, problemContext: String, history: [ChatMessage]) async throws -> String {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return DemoFixtures.chatReply
        }
        isLoadingChat = true
        defer { isLoadingChat = false }

        let systemPrompt = """
        You are a friendly, patient math tutor. The student is working on this problem: '\(problemContext)'. \
        They've already seen the lesson and step-by-step solution. \
        Answer their follow-up questions clearly and encouragingly. Use simple language. \
        If they're confused, try explaining differently with an analogy.
        """

        var messages: [ClaudeMessage] = []
        for msg in history {
            messages.append(ClaudeMessage(role: msg.role.rawValue, content: msg.content))
        }
        messages.append(ClaudeMessage(role: "user", content: message))

        let response = try await sendMessages(messages, system: systemPrompt)
        return response
    }

    // MARK: - Problem Detection (Claude Vision)

    func detectProblems(in image: UIImage) async throws -> [DetectedProblem] {
        if DemoMode.isEnabled {
            await DemoMode.pause()
            return try DemoMode.decode([DetectedProblem].self, from: DemoFixtures.detectedProblems, label: "detection")
        }
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
        let data = Data(extracted.utf8)
        do {
            return try JSONDecoder().decode([DetectedProblem].self, from: data)
        } catch {
            throw ClaudeError.decodingFailed(context: "problem detection")
        }
    }

    // MARK: - Problem Title from Image

    func generateProblemTitle(from image: UIImage) async -> String {
        if DemoMode.isEnabled { return DemoFixtures.title }
        do {
            let prompt = """
            Look at this math problem image. Respond with ONLY a 3-5 word title summarizing what the problem is about. Examples: "Surface Area Integral", "Curl of Vector Field", "Quadratic Factoring", "Taylor Series Expansion", "Double Integral Polar".

            Respond with ONLY the short title, nothing else. No quotes, no period, no explanation.
            """
            let response = try await sendImageMessage(image, prompt: prompt)
            let title = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count <= 60 && !title.isEmpty {
                return title
            }
            let words = title.split(separator: " ").prefix(5).joined(separator: " ")
            return words.isEmpty ? "Scanned Problem" : words
        } catch {
            return "Scanned Problem"
        }
    }

    func generateProblemTitle(from text: String) async -> String {
        if DemoMode.isEnabled { return DemoFixtures.title }
        do {
            let prompt = """
            Here is a math problem: '\(text)'

            Respond with ONLY a 3-5 word title summarizing what this problem is about. Examples: "Surface Area Integral", "Curl of Vector Field", "Quadratic Factoring".

            Respond with ONLY the short title, nothing else.
            """
            let response = try await sendMessage(prompt)
            let title = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count <= 60 && !title.isEmpty {
                return title
            }
            let words = title.split(separator: " ").prefix(5).joined(separator: " ")
            return words.isEmpty ? String(text.prefix(40)) : words
        } catch {
            return String(text.prefix(40))
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
        } catch let error as ClaudeError {
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
            throw ClaudeError.networkUnavailable
        }
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }
        guard let base64 = imageBase64(image) else {
            throw ClaudeError.invalidResponse
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
                throw ClaudeError.networkUnavailable
            case .timedOut:
                throw ClaudeError.timeout
            default:
                throw ClaudeError.apiError(urlError.localizedDescription)
            }
        }

        guard let http = httpResponse as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "no body"
            print("[ClaudeAPI] Image HTTP \(http.statusCode): \(bodyString)")

            switch http.statusCode {
            case 401: throw ClaudeError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap { TimeInterval($0) }
                throw ClaudeError.rateLimited(retryAfter: retryAfter)
            case 500...599: throw ClaudeError.serverError(statusCode: http.statusCode)
            default:
                let apiResponse = try? JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
                let msg = apiResponse?.error?.message ?? "Status \(http.statusCode)"
                throw ClaudeError.apiError(msg)
            }
        }

        let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
        guard let text = apiResponse.text else {
            throw ClaudeError.emptyResponse
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

        throw ClaudeError.decodingFailed(context: "\(context): could not parse response")
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

    private func sendMessage(_ content: String, system: String? = nil) async throws -> String {
        let messages = [ClaudeMessage(role: "user", content: content)]
        return try await sendMessages(messages, system: system)
    }

    private func sendMessages(_ messages: [ClaudeMessage], system: String? = nil) async throws -> String {
        // One release, on every path, including cancellation. The previous
        // version released at five separate call sites; a slot missed at any of
        // them is gone for the life of the process, and after four the app stops
        // making requests with nothing on screen to say why.
        try await requestQueue.withSlot {
            do {
                return try await self.performRequest(messages, system: system)
            } catch let error as ClaudeError {
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
            throw ClaudeError.networkUnavailable
        }

        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
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
                throw ClaudeError.networkUnavailable
            case .timedOut:
                throw ClaudeError.timeout
            default:
                throw ClaudeError.apiError(urlError.localizedDescription)
            }
        }

        guard let http = httpResponse as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard http.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? "no body"
            print("[ClaudeAPI] HTTP \(http.statusCode): \(bodyString)")

            switch http.statusCode {
            case 401:
                throw ClaudeError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap { TimeInterval($0) }
                throw ClaudeError.rateLimited(retryAfter: retryAfter)
            case 500...599:
                throw ClaudeError.serverError(statusCode: http.statusCode)
            default:
                let apiResponse = try? JSONDecoder().decode(ClaudeAPIResponse.self, from: data)
                let msg = apiResponse?.error?.message ?? "Status \(http.statusCode)"
                throw ClaudeError.apiError(msg)
            }
        }

        let apiResponse = try JSONDecoder().decode(ClaudeAPIResponse.self, from: data)

        guard let text = apiResponse.text else {
            throw ClaudeError.emptyResponse
        }

        return text
    }

    // MARK: - Errors

    enum ClaudeError: LocalizedError, Equatable {
        case noAPIKey
        case invalidResponse
        case apiError(String)
        case emptyResponse
        case networkUnavailable
        case timeout
        case rateLimited(retryAfter: TimeInterval?)
        case unauthorized
        case serverError(statusCode: Int)
        case decodingFailed(context: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key found. Please add your Anthropic API key in Settings."
            case .invalidResponse:
                return "Received an invalid response from the server."
            case .apiError(let message):
                return "API Error: \(message)"
            case .emptyResponse:
                return "Received an empty response."
            case .networkUnavailable:
                return "No internet connection. Please check your network and try again."
            case .timeout:
                return "The request timed out. Please try again."
            case .rateLimited:
                return "Too many requests. Please wait a moment and try again."
            case .unauthorized:
                return "Invalid API key. Please check your key in Settings."
            case .serverError(let statusCode):
                return "Server error (\(statusCode)). Please try again later."
            case .decodingFailed(let context):
                let label = context.components(separatedBy: ":").first ?? context
                return "Could not parse \(label). The AI response was in an unexpected format. Try again."
            }
        }

        var debugDetail: String? {
            switch self {
            case .decodingFailed(let context) where context.contains(":"):
                return String(context.dropFirst((context.components(separatedBy: ":").first?.count ?? 0) + 2))
            case .apiError(let message):
                return message
            default:
                return nil
            }
        }

        var icon: String {
            switch self {
            case .noAPIKey, .unauthorized: return "key.slash.fill"
            case .networkUnavailable: return "wifi.slash"
            case .timeout: return "clock.badge.exclamationmark"
            case .rateLimited: return "gauge.with.dots.needle.67percent"
            case .serverError: return "server.rack"
            case .decodingFailed: return "doc.questionmark.fill"
            default: return "exclamationmark.triangle.fill"
            }
        }

        var title: String {
            switch self {
            case .noAPIKey: return "API Key Missing"
            case .unauthorized: return "Invalid API Key"
            case .networkUnavailable: return "You're Offline"
            case .timeout: return "Request Timed Out"
            case .rateLimited: return "Too Many Requests"
            case .serverError: return "Server Error"
            case .decodingFailed: return "Parsing Error"
            case .invalidResponse: return "Invalid Response"
            case .apiError: return "API Error"
            case .emptyResponse: return "Empty Response"
            }
        }
    }
}
