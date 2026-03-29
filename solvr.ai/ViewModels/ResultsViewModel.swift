import SwiftUI
import SwiftData

@Observable
final class ResultsViewModel {

    // MARK: - Content
    var lesson: LessonContent?
    var steps: [StepItem]?
    var formulas: [FormulaItem]?
    var videos: [VideoItem]?

    // MARK: - API errors
    var lessonError: ClaudeAPIManager.ClaudeError?
    var stepsError: ClaudeAPIManager.ClaudeError?
    var formulasError: ClaudeAPIManager.ClaudeError?
    var videosError: ClaudeAPIManager.ClaudeError?

    var selectedTab: ResultTab = .steps
    var showConfetti: Bool = false

    private(set) var currentProblem: String = ""
    var problemTitle: String = ""

    // Source image from camera scanner
    var sourceImage: UIImage?

    private let api = ClaudeAPIManager.shared

    var isLoadingLesson: Bool { api.isLoadingLesson }
    var isLoadingSteps: Bool { api.isLoadingSteps }
    var isLoadingFormulas: Bool { api.isLoadingFormulas }
    var isLoadingVideos: Bool { api.isLoadingVideos }

    var isLoadingAny: Bool {
        isLoadingLesson || isLoadingSteps || isLoadingFormulas || isLoadingVideos
    }

    // MARK: - Solve (text)

    func solveAll(problem: String) {
        currentProblem = problem
        problemTitle = problem
        resetState()

        Task { await fetchLesson(problem) }
        Task { await fetchSteps(problem) }
        Task { await fetchFormulas(problem) }
        Task { await fetchVideos(problem) }
    }

    // MARK: - Solve (image)

    func solveFromImage(_ image: UIImage) {
        sourceImage = image
        currentProblem = "[Scanned Image]"
        problemTitle = ""
        resetState()

        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchLessonFromImage(image) }
                group.addTask { await self.fetchStepsFromImage(image) }
                group.addTask { await self.fetchFormulasFromImage(image) }
                group.addTask { await self.fetchVideosFromImage(image) }
                group.addTask {
                    let title = await ClaudeAPIManager.shared.generateProblemTitle(from: image)
                    await MainActor.run {
                        self.problemTitle = title
                        self.currentProblem = title
                    }
                }
            }
        }
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

    // MARK: - Text fetchers

    private func fetchLesson(_ problem: String) async {
        do {
            let result = try await api.fetchLesson(for: problem)
            await MainActor.run { lesson = result }
        } catch {
            await MainActor.run {
                lessonError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchSteps(_ problem: String) async {
        do {
            let result = try await api.fetchSteps(for: problem)
            await MainActor.run { steps = result }
        } catch {
            await MainActor.run {
                stepsError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchFormulas(_ problem: String) async {
        do {
            let result = try await api.fetchFormulas(for: problem)
            await MainActor.run { formulas = result }
        } catch {
            await MainActor.run {
                formulasError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchVideos(_ problem: String) async {
        do {
            let result = try await api.fetchVideos(for: problem)
            await MainActor.run { videos = result }
        } catch {
            await MainActor.run {
                videosError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    // MARK: - Image fetchers

    private func fetchLessonFromImage(_ image: UIImage) async {
        do {
            let result = try await api.fetchLessonFromImage(image)
            await MainActor.run { lesson = result }
        } catch {
            await MainActor.run {
                lessonError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchStepsFromImage(_ image: UIImage) async {
        do {
            let result = try await api.fetchStepsFromImage(image)
            await MainActor.run { steps = result }
        } catch {
            await MainActor.run {
                stepsError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchFormulasFromImage(_ image: UIImage) async {
        do {
            let result = try await api.fetchFormulasFromImage(image)
            await MainActor.run { formulas = result }
        } catch {
            await MainActor.run {
                formulasError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
            }
        }
    }

    private func fetchVideosFromImage(_ image: UIImage) async {
        do {
            let result = try await api.fetchVideosFromImage(image)
            await MainActor.run { videos = result }
        } catch {
            await MainActor.run {
                videosError = (error as? ClaudeAPIManager.ClaudeError) ?? .apiError(error.localizedDescription)
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
        if sourceImage != nil {
            Task { await fetchLessonFromImage(sourceImage!) }
        } else {
            Task { await fetchLesson(currentProblem) }
        }
    }

    func retrySteps() {
        stepsError = nil
        steps = nil
        if sourceImage != nil {
            Task { await fetchStepsFromImage(sourceImage!) }
        } else {
            Task { await fetchSteps(currentProblem) }
        }
    }

    func retryFormulas() {
        formulasError = nil
        formulas = nil
        if sourceImage != nil {
            Task { await fetchFormulasFromImage(sourceImage!) }
        } else {
            Task { await fetchFormulas(currentProblem) }
        }
    }

    func retryVideos() {
        videosError = nil
        videos = nil
        if sourceImage != nil {
            Task { await fetchVideosFromImage(sourceImage!) }
        } else {
            Task { await fetchVideos(currentProblem) }
        }
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
