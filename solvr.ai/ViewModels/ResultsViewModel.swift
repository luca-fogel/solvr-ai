import SwiftUI
import SwiftData
import SolvrCore

@Observable
final class ResultsViewModel {

    // MARK: - Content
    var lesson: LessonContent?
    var steps: [StepItem]?
    var formulas: [FormulaItem]?
    var videos: [VideoItem]?

    // MARK: - API errors
    var lessonError: SolverError?
    var stepsError: SolverError?
    var formulasError: SolverError?
    var videosError: SolverError?

    var selectedTab: ResultTab = .steps
    var showConfetti: Bool = false

    private(set) var currentProblem: String = ""
    var problemTitle: String = ""

    // Source image from camera scanner
    var sourceImage: UIImage?

    /// The last thing we were asked, so a retry can re-ask it. A photograph is
    /// kept as the bytes that were sent rather than the `UIImage`, so a retry is
    /// byte-identical to the original request.
    private var currentInput: ProblemInput = .text("")

    // Owned here, not read off the provider. Four fetches run concurrently, and
    // while there was exactly one backend it was harmless for them to share five
    // booleans on a singleton. With more than one provider -- and one of them
    // serving a single request at a time -- loading state belongs to the screen
    // that displays it, not to whatever answered.
    var isLoadingLesson = false
    var isLoadingSteps = false
    var isLoadingFormulas = false
    var isLoadingVideos = false

    var isLoadingAny: Bool {
        isLoadingLesson || isLoadingSteps || isLoadingFormulas || isLoadingVideos
    }

    // MARK: - Solve

    func solveAll(problem: String) {
        currentProblem = problem
        problemTitle = problem
        solve(.text(problem))
    }

    func solveFromImage(_ image: UIImage) {
        sourceImage = image
        currentProblem = "[Scanned Image]"
        problemTitle = ""
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            resetState()
            let failure = SolverError.invalidResponse
            lessonError = failure
            stepsError = failure
            formulasError = failure
            videosError = failure
            return
        }
        solve(.image(jpeg))

        Task {
            let title = await ProviderFactory.current().title(for: .image(jpeg))
            await MainActor.run {
                self.problemTitle = title
                self.currentProblem = title
            }
        }
    }

    /// One path for both, which is the point of `ProblemInput`.
    ///
    /// The two used to be separate: four methods for typed problems and four
    /// near-identical ones for photographs, differing only in which API call they
    /// made. Whether a backend can read a photograph is now the provider's
    /// business -- `ProviderFactory` wraps the ones that cannot -- so this layer
    /// no longer knows or cares.
    private func solve(_ input: ProblemInput) {
        currentInput = input
        resetState()

        // Steps first, deliberately. Against a hosted API all four run at once
        // and the order is cosmetic. The on-device model serves one request at a
        // time -- `GenerationError.concurrentRequests` is real -- so these queue,
        // and steps is the tab that opens by default. Asking for it first is the
        // difference between the screen filling in and the screen waiting.
        Task { await fetchSteps(input) }
        Task { await fetchLesson(input) }
        Task { await fetchFormulas(input) }
        Task { await fetchVideos(input) }
    }

    private func resetState() {
        lesson = nil
        steps = nil
        formulas = nil
        videos = nil
        lessonError = nil
        stepsError = nil
        formulasError = nil
        videosError = nil
        showConfetti = false
        selectedTab = .steps
    }

    // MARK: - Fetchers

    private func fetchLesson(_ input: ProblemInput) async {
        isLoadingLesson = true
        defer { isLoadingLesson = false }
        do {
            let result = try await ProviderFactory.current().lesson(for: input)
            await MainActor.run { lesson = result }
        } catch {
            await MainActor.run {
                lessonError = (error as? SolverError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchSteps(_ input: ProblemInput) async {
        isLoadingSteps = true
        defer { isLoadingSteps = false }
        do {
            let result = try await ProviderFactory.current().steps(for: input)
            await MainActor.run { steps = result }
        } catch {
            await MainActor.run {
                stepsError = (error as? SolverError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchFormulas(_ input: ProblemInput) async {
        isLoadingFormulas = true
        defer { isLoadingFormulas = false }
        do {
            let result = try await ProviderFactory.current().formulas(for: input)
            await MainActor.run { formulas = result }
        } catch {
            await MainActor.run {
                formulasError = (error as? SolverError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchVideos(_ input: ProblemInput) async {
        isLoadingVideos = true
        defer { isLoadingVideos = false }
        do {
            let result = try await ProviderFactory.current().videos(for: input)
            await MainActor.run { videos = result }
        } catch {
            await MainActor.run {
                videosError = (error as? SolverError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    // MARK: - Load from History

    func loadFromHistory(_ problem: Problem) {
        currentProblem = problem.text
        lessonError = nil
        stepsError = nil
        formulasError = nil
        videosError = nil
        selectedTab = .steps
        showConfetti = false

        // Restore source image
        if let data = problem.sourceImageData {
            sourceImage = UIImage(data: data)
        } else {
            sourceImage = nil
        }

        // Load cached lesson
        if let json = problem.lessonJSON, let data = json.data(using: .utf8) {
            lesson = try? JSONDecoder().decode(LessonContent.self, from: data)
        } else {
            lesson = nil
        }

        if let json = problem.stepsJSON, let data = json.data(using: .utf8) {
            steps = try? JSONDecoder().decode([StepItem].self, from: data)
        } else {
            steps = nil
        }

        if let json = problem.formulasJSON, let data = json.data(using: .utf8) {
            formulas = try? JSONDecoder().decode([FormulaItem].self, from: data)
        } else {
            formulas = nil
        }

        if let json = problem.videosJSON, let data = json.data(using: .utf8) {
            videos = try? JSONDecoder().decode([VideoItem].self, from: data)
        } else {
            videos = nil
        }
    }

    // MARK: - Retry

    func retryLesson() {
        lessonError = nil
        lesson = nil
        Task { await fetchLesson(currentInput) }
    }

    func retrySteps() {
        stepsError = nil
        steps = nil
        Task { await fetchSteps(currentInput) }
    }

    func retryFormulas() {
        formulasError = nil
        formulas = nil
        Task { await fetchFormulas(currentInput) }
    }

    func retryVideos() {
        videosError = nil
        videos = nil
        Task { await fetchVideos(currentInput) }
    }

    // MARK: - Save to History

    @discardableResult
    func saveProblem(_ problemText: String, context: ModelContext) -> Problem {
        let displayText = problemTitle.isEmpty ? problemText : problemTitle
        let problem = Problem(
            text: displayText,
            formulasJSON: formulas.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            stepsJSON: steps.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            videosJSON: videos.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            lessonJSON: lesson.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) },
            sourceImageData: sourceImage?.jpegData(compressionQuality: 0.7)
        )
        context.insert(problem)
        return problem
    }
}

// MARK: - Result Tab

enum ResultTab: Int, CaseIterable, Identifiable {
    case steps = 0
    case lesson = 1
    case formulas = 2
    case videos = 3
    case chat = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .steps: return "Steps"
        case .lesson: return "Lesson"
        case .formulas: return "Formulas"
        case .videos: return "Video"
        case .chat: return "Chat"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "number"
        case .lesson: return "book.fill"
        case .formulas: return "function"
        case .videos: return "play.rectangle.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }
}
