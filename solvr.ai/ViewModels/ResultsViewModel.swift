import SwiftUI
import SwiftData
import SolvrCore

/// The results screen's adapter onto `SolvrCore.SolveCoordinator`.
///
/// Everything that decides *what the model is asked* now lives in the package,
/// where `swift test` can drive it with a spy provider. What is left here is
/// the part that genuinely needs the app: `UIImage`, SwiftData, and which tab
/// is on screen.
///
/// The split is not cosmetic. The bug that produced a lesson about flatbed
/// scanners from a photograph of an integral lived in this file, in the
/// relationship between the string being displayed and the string being asked
/// about, and there was no test in the repository that could reach it.
@Observable
@MainActor
final class ResultsViewModel {

    private let coordinator = SolveCoordinator(provider: { ProviderFactory.current() })

    /// Which tab is on screen. Stays here: it includes Chat, which is not a
    /// surface any provider is asked for.
    var selectedTab: ResultTab = .steps

    /// Source image from the camera scanner.
    var sourceImage: UIImage?

    // MARK: - Content, forwarded

    var stepsState: SurfaceState<[StepItem]> { coordinator.stepsState }
    var lessonState: SurfaceState<LessonContent> { coordinator.lessonState }
    var formulasState: SurfaceState<[FormulaItem]> { coordinator.formulasState }
    var videosState: SurfaceState<[VideoItem]> { coordinator.videosState }

    var steps: [StepItem]? { coordinator.steps }
    var lesson: LessonContent? { coordinator.lesson }
    var formulas: [FormulaItem]? { coordinator.formulas }
    var videos: [VideoItem]? { coordinator.videos }

    var currentProblem: String { coordinator.currentProblem }
    var problemTitle: String { coordinator.problemTitle }
    var isLoadingAny: Bool { coordinator.isLoadingAny }

    // MARK: - Solve

    func solveAll(problem: String) {
        sourceImage = nil
        selectedTab = .steps
        coordinator.solveAll(problem: problem)
    }

    func solveFromImage(_ image: UIImage) {
        sourceImage = image
        selectedTab = .steps
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            coordinator.failEverything(with: .invalidResponse)
            return
        }
        coordinator.solveFromImage(jpeg: jpeg, placeholder: "[Scanned Image]")
    }

    func ensureLoaded(_ tab: ResultTab) {
        guard let surface = tab.surface else { return }   // Chat generates per message.
        coordinator.ensureLoaded(surface)
    }

    // MARK: - Load from history

    func loadFromHistory(_ problem: Problem) {
        selectedTab = .steps
        sourceImage = problem.sourceImageData.flatMap(UIImage.init(data:))
        coordinator.loadFromHistory(text: problem.text,
                                    stepsJSON: problem.stepsJSON,
                                    lessonJSON: problem.lessonJSON,
                                    formulasJSON: problem.formulasJSON,
                                    videosJSON: problem.videosJSON)
    }

    // MARK: - Retry

    func retrySteps() { coordinator.retry(.steps) }
    func retryLesson() { coordinator.retry(.lesson) }
    func retryFormulas() { coordinator.retry(.formulas) }
    func retryVideos() { coordinator.retry(.videos) }

    // MARK: - Save to history

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

    /// The provider surface this tab shows, or `nil` for Chat, which is
    /// generated per message rather than per solve.
    var surface: Surface? {
        switch self {
        case .steps: return .steps
        case .lesson: return .lesson
        case .formulas: return .formulas
        case .videos: return .videos
        case .chat: return nil
        }
    }

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
