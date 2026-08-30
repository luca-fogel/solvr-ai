import SwiftUI
import SwiftData
import SolvrCore

@Observable
@MainActor
final class ResultsViewModel {

    // MARK: - Content
    //
    // One state per tab, rather than a value, an error and a loading flag each.
    // Sixteen combinations described four real ones, and the combination nobody
    // wrote a branch for -- not loading, no error, no content -- drew a blank
    // screen in all four views.
    var stepsState: SurfaceState<[StepItem]> = .idle
    var lessonState: SurfaceState<LessonContent> = .idle
    var formulasState: SurfaceState<[FormulaItem]> = .idle
    var videosState: SurfaceState<[VideoItem]> = .idle

    // Read by history saving and the accessibility summary, which want the
    // content and do not care how it got here.
    var steps: [StepItem]? { stepsState.value }
    var lesson: LessonContent? { lessonState.value }
    var formulas: [FormulaItem]? { formulasState.value }
    var videos: [VideoItem]? { videosState.value }

    var selectedTab: ResultTab = .steps

    private(set) var currentProblem: String = ""
    var problemTitle: String = ""

    // Source image from camera scanner
    var sourceImage: UIImage?

    /// The last thing we were asked, so a retry can re-ask it. A photograph is
    /// kept as the bytes that were sent rather than the `UIImage`, so a retry is
    /// byte-identical to the original request.
    private var currentInput: ProblemInput = .text("")

    /// Which solve the results on screen belong to.
    ///
    /// Backing out of a problem and solving another one used to leave the first
    /// solve's requests in flight, still holding a reference to this view model,
    /// still writing their answers into it when they finished. The answer for
    /// the previous question would then appear under the new one -- which looks
    /// exactly like a model that ignored the question. Every request carries the
    /// id it was issued under and a stale one is dropped on arrival.
    private var solveID = UUID()

    /// The tail of the request chain.
    ///
    /// The on-device model serves one request at a time (`RequestQueue(maxConcurrent: 1)`
    /// inside the provider, and `GenerationError.concurrentRequests` behind that).
    /// Four detached `Task`s therefore did not run in parallel; they ran in
    /// whatever order the scheduler happened to start them, which is why the
    /// Videos tab could fill in before the Steps tab the user was staring at.
    /// Each new request now awaits the previous one, so the order is the order
    /// they were asked for.
    private var tail: Task<Void, Never>?

    var isLoadingAny: Bool {
        stepsState.isLoading || lessonState.isLoading
            || formulasState.isLoading || videosState.isLoading
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
            stepsState = .failed(failure)
            lessonState = .failed(failure)
            formulasState = .failed(failure)
            videosState = .failed(failure)
            return
        }
        solve(.image(jpeg))

        let id = solveID
        Task {
            let title = await ProviderFactory.current().title(for: .image(jpeg))
            await MainActor.run {
                guard self.solveID == id else { return }
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

        // Steps only. The other three surfaces are generated when their tab is
        // opened -- see `ensureLoaded`. On a device that answers one request at
        // a time, asking for four means the first answer arrives after one
        // generation and the last after four; most students never open Videos.
        enqueue(.steps)
    }

    private func resetState() {
        solveID = UUID()
        tail?.cancel()
        tail = nil
        stepsState = .idle
        lessonState = .idle
        formulasState = .idle
        videosState = .idle
        selectedTab = .steps
    }

    /// Fetch a tab the first time it is looked at.
    ///
    /// Called from the view when the selection changes. Idempotent: a tab that
    /// is loading, loaded or failed is left alone, so switching back and forth
    /// does not re-ask.
    func ensureLoaded(_ tab: ResultTab) {
        guard !currentProblem.isEmpty else { return }
        switch tab {
        case .steps: if stepsState.isIdle { enqueue(.steps) }
        case .lesson: if lessonState.isIdle { enqueue(.lesson) }
        case .formulas: if formulasState.isIdle { enqueue(.formulas) }
        case .videos: if videosState.isIdle { enqueue(.videos) }
        case .chat: break   // Chat generates per message, on demand.
        }
    }

    // MARK: - The request chain

    private func enqueue(_ tab: ResultTab) {
        let input = currentInput
        let id = solveID
        setLoading(tab)

        let previous = tail
        tail = Task { @MainActor [weak self] in
            // Wait for whatever was asked for first. Not cancelling it: a
            // cancelled generation returns nothing, so cancelling to jump the
            // queue throws away the seconds already spent on a surface the user
            // will probably still want.
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.fetch(tab, input: input, id: id)
        }
    }

    private func setLoading(_ tab: ResultTab) {
        switch tab {
        case .steps: stepsState = .loading
        case .lesson: lessonState = .loading
        case .formulas: formulasState = .loading
        case .videos: videosState = .loading
        case .chat: break
        }
    }

    private func fetch(_ tab: ResultTab, input: ProblemInput, id: UUID) async {
        let provider = ProviderFactory.current()
        do {
            switch tab {
            case .steps:
                let result = try await provider.steps(for: input)
                await apply(id) { $0.stepsState = result.isEmpty ? .empty : .ready(result) }
            case .lesson:
                let result = try await provider.lesson(for: input)
                await apply(id) { $0.lessonState = .ready(result) }
            case .formulas:
                let result = try await provider.formulas(for: input)
                await apply(id) { $0.formulasState = result.isEmpty ? .empty : .ready(result) }
            case .videos:
                let result = try await provider.videos(for: input)
                await apply(id) { $0.videosState = result.isEmpty ? .empty : .ready(result) }
            case .chat:
                return
            }
        } catch {
            let failure = (error as? SolverError) ?? .apiError(error.localizedDescription)
            await apply(id) { model in
                switch tab {
                case .steps: model.stepsState = .failed(failure)
                case .lesson: model.lessonState = .failed(failure)
                case .formulas: model.formulasState = .failed(failure)
                case .videos: model.videosState = .failed(failure)
                case .chat: break
                }
            }
        }
    }

    /// Write a result only if it belongs to the solve that is on screen.
    private func apply(_ id: UUID, _ change: (ResultsViewModel) -> Void) {
        guard solveID == id else { return }
        change(self)
    }

    // MARK: - Load from History

    func loadFromHistory(_ problem: Problem) {
        resetState()
        currentProblem = problem.text

        // Restore source image
        if let data = problem.sourceImageData {
            sourceImage = UIImage(data: data)
        } else {
            sourceImage = nil
        }

        stepsState = Self.restore([StepItem].self, from: problem.stepsJSON)
        lessonState = Self.restore(LessonContent.self, from: problem.lessonJSON)
        formulasState = Self.restore([FormulaItem].self, from: problem.formulasJSON)
        videosState = Self.restore([VideoItem].self, from: problem.videosJSON)
    }

    /// A saved surface, or `idle` -- which for a history entry means the tab was
    /// never opened when the problem was solved, and opening it now will ask.
    private static func restore<T: Decodable & Sendable>(
        _ type: T.Type, from json: String?
    ) -> SurfaceState<T> {
        guard let json, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { return .idle }
        return .ready(value)
    }

    // MARK: - Retry

    func retrySteps() { retry(.steps) }
    func retryLesson() { retry(.lesson) }
    func retryFormulas() { retry(.formulas) }
    func retryVideos() { retry(.videos) }

    /// A retry is a person waiting, so it goes to the front rather than behind
    /// whatever speculative surface is in flight.
    private func retry(_ tab: ResultTab) {
        tail?.cancel()
        tail = nil
        enqueue(tab)
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
