import Foundation
import Observation

/// The four surfaces of one solve, and the order they are asked for in.
///
/// Separate from the app's `ResultTab`, which also has a Chat case and carries
/// SF Symbol names. This is the set of things a *provider* can be asked for, and
/// it lives here because the logic that decides what to ask, when, and with what
/// input is the logic that got the answer wrong -- and it could not be tested
/// while it lived in a view model in the app target.
public enum Surface: String, CaseIterable, Sendable, Hashable {
    case steps, lesson, formulas, videos
}

/// Owns one solve: what was asked, which surfaces have been asked for, and what
/// came back.
///
/// This used to be `ResultsViewModel` in the app target, where `swift test`
/// could not reach it. That mattered more than it sounds. The bug that produced
/// a lesson about flatbed scanners from a photograph of an integral was here,
/// in the relationship between *what is displayed* and *what is asked*, and
/// there was no test in the repository that could have expressed it.
@Observable
@MainActor
public final class SolveCoordinator {

    // MARK: - Content

    /// One state per surface, rather than a value, an error and a loading flag
    /// each. Sixteen combinations described four real ones, and the combination
    /// nobody wrote a branch for -- not loading, no error, no content -- drew a
    /// blank screen in all four views.
    public var stepsState: SurfaceState<[StepItem]> = .idle
    public var lessonState: SurfaceState<LessonContent> = .idle
    public var formulasState: SurfaceState<[FormulaItem]> = .idle
    public var videosState: SurfaceState<[VideoItem]> = .idle

    public var steps: [StepItem]? { stepsState.value }
    public var lesson: LessonContent? { lessonState.value }
    public var formulas: [FormulaItem]? { formulasState.value }
    public var videos: [VideoItem]? { videosState.value }

    public private(set) var currentProblem: String = ""
    public var problemTitle: String = ""

    /// The last thing we were asked, so a retry can re-ask it. A photograph is
    /// kept as the bytes that were sent rather than as an image, so a retry is
    /// byte-identical to the original request.
    private var currentInput: ProblemInput = .text("")

    /// Which solve the results on screen belong to.
    ///
    /// Backing out of a problem and solving another one used to leave the first
    /// solve's requests in flight, still writing their answers in when they
    /// finished. Every request carries the id it was issued under and a stale
    /// one is dropped on arrival.
    private var solveID = UUID()

    /// The tail of the request chain. The on-device model serves one request at
    /// a time, so four detached tasks did not run in parallel -- they ran in
    /// whatever order the scheduler started them. Each new request awaits the
    /// previous one, so the order is the order they were asked for.
    private var tail: Task<Void, Never>?

    /// Resolved per request, not cached, so a settings change takes effect on
    /// the next fetch rather than at the next launch.
    private let provider: @Sendable () -> any SolutionProvider

    public init(provider: @escaping @Sendable () -> any SolutionProvider) {
        self.provider = provider
    }

    public var isLoadingAny: Bool {
        stepsState.isLoading || lessonState.isLoading
            || formulasState.isLoading || videosState.isLoading
    }

    // MARK: - Solve

    public func solveAll(problem: String) {
        currentProblem = problem
        problemTitle = problem
        solve(.text(problem))
    }

    /// A photograph. `title` is fetched separately and asynchronously, because a
    /// missing title is cosmetic and must never fail a solve.
    public func solveFromImage(jpeg: Data, placeholder: String) {
        currentProblem = placeholder
        problemTitle = ""
        solve(.image(jpeg))

        let id = solveID
        titleTask = Task { [weak self] in
            guard let self else { return }
            let title = await self.provider().title(for: .image(jpeg))
            guard self.solveID == id else { return }
            self.problemTitle = title
            self.currentProblem = title
        }
    }

    /// The title generation, which runs outside the surface chain.
    private var titleTask: Task<Void, Never>?

    /// Await everything this coordinator has in flight.
    ///
    /// Internal, for tests. The chain is a linked list of tasks each awaiting
    /// its predecessor, so awaiting the tail awaits all of them; the title is
    /// deliberately not in that chain and has to be awaited separately.
    func settle() async {
        await titleTask?.value
        await tail?.value
    }

    /// One path for both, which is the point of `ProblemInput`.
    private func solve(_ input: ProblemInput) {
        currentInput = input
        resetState()

        // Steps only. The other three surfaces are generated when their tab is
        // opened -- see `ensureLoaded`. On a device that answers one request at
        // a time, asking for four means the first answer arrives after one
        // generation and the last after four; most students never open Videos.
        enqueue(.steps)
    }

    /// Put every surface into the same failure, for something that went wrong
    /// before any request could be made -- a photograph that would not encode,
    /// or a photograph nothing could be read from.
    public func failEverything(with error: SolverError) {
        resetState()
        stepsState = .failed(error)
        lessonState = .failed(error)
        formulasState = .failed(error)
        videosState = .failed(error)
    }

    public func resetState() {
        solveID = UUID()
        tail?.cancel()
        tail = nil
        stepsState = .idle
        lessonState = .idle
        formulasState = .idle
        videosState = .idle
    }

    /// Fetch a surface the first time it is looked at.
    ///
    /// Idempotent: a surface that is loading, loaded or failed is left alone, so
    /// switching back and forth does not re-ask.
    public func ensureLoaded(_ surface: Surface) {
        guard !currentProblem.isEmpty else { return }
        guard state(for: surface).isIdle else { return }
        enqueue(surface)
    }

    // MARK: - The request chain

    private func enqueue(_ surface: Surface) {
        let input = currentInput
        let id = solveID
        setLoading(surface)

        let previous = tail
        tail = Task { @MainActor [weak self] in
            // Wait for whatever was asked for first. Not cancelling it: a
            // cancelled generation returns nothing, so cancelling to jump the
            // queue throws away the seconds already spent on a surface the user
            // will probably still want.
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.fetch(surface, input: input, id: id)
        }
    }

    private func fetch(_ surface: Surface, input: ProblemInput, id: UUID) async {
        let provider = self.provider()
        do {
            switch surface {
            case .steps:
                let result = try await provider.steps(for: input)
                apply(id) { $0.stepsState = result.isEmpty ? .empty : .ready(result) }
            case .lesson:
                let result = try await provider.lesson(for: input)
                apply(id) { $0.lessonState = .ready(result) }
            case .formulas:
                let result = try await provider.formulas(for: input)
                apply(id) { $0.formulasState = result.isEmpty ? .empty : .ready(result) }
            case .videos:
                let result = try await provider.videos(for: input)
                apply(id) { $0.videosState = result.isEmpty ? .empty : .ready(result) }
            }
        } catch {
            let failure = (error as? SolverError) ?? .apiError(error.localizedDescription)
            apply(id) { $0.set(surface, .failed(failure)) }
        }
    }

    /// Write a result only if it belongs to the solve that is on screen.
    private func apply(_ id: UUID, _ change: (SolveCoordinator) -> Void) {
        guard solveID == id else { return }
        change(self)
    }

    // MARK: - Load from history

    /// Restore a saved solve. `text` is what was stored against it, and any
    /// surface that was never saved is left `idle` so opening it asks.
    public func loadFromHistory(text: String,
                                stepsJSON: String?,
                                lessonJSON: String?,
                                formulasJSON: String?,
                                videosJSON: String?) {
        resetState()
        currentProblem = text
        // What a surface left unsaved will be regenerated from. Without this the
        // input is still whatever was solved last -- or empty on a cold launch
        // into History -- and opening an unsaved surface would ask the model to
        // solve nothing.
        currentInput = .text(text)

        stepsState = Self.restore([StepItem].self, from: stepsJSON)
        lessonState = Self.restore(LessonContent.self, from: lessonJSON)
        formulasState = Self.restore([FormulaItem].self, from: formulasJSON)
        videosState = Self.restore(VideoItem.self.arrayType, from: videosJSON)
    }

    private static func restore<T: Decodable & Sendable>(
        _ type: T.Type, from json: String?
    ) -> SurfaceState<T> {
        guard let json, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { return .idle }
        return .ready(value)
    }

    // MARK: - Retry

    /// A retry is a person waiting, so it goes to the front rather than behind
    /// whatever speculative surface is in flight.
    public func retry(_ surface: Surface) {
        tail?.cancel()
        tail = nil
        enqueue(surface)
    }

    // MARK: - Surface state access

    public func state(for surface: Surface) -> AnySurfaceState {
        switch surface {
        case .steps: return AnySurfaceState(stepsState)
        case .lesson: return AnySurfaceState(lessonState)
        case .formulas: return AnySurfaceState(formulasState)
        case .videos: return AnySurfaceState(videosState)
        }
    }

    private func setLoading(_ surface: Surface) { set(surface, .loading) }

    /// Write the same case into whichever surface, without caring about its
    /// value type. Only the value-free cases are expressible here, which is all
    /// the chain ever needs to write.
    private func set(_ surface: Surface, _ state: ValuelessSurfaceState) {
        switch (surface, state) {
        case (.steps, .idle): stepsState = .idle
        case (.steps, .loading): stepsState = .loading
        case (.steps, .failed(let e)): stepsState = .failed(e)
        case (.lesson, .idle): lessonState = .idle
        case (.lesson, .loading): lessonState = .loading
        case (.lesson, .failed(let e)): lessonState = .failed(e)
        case (.formulas, .idle): formulasState = .idle
        case (.formulas, .loading): formulasState = .loading
        case (.formulas, .failed(let e)): formulasState = .failed(e)
        case (.videos, .idle): videosState = .idle
        case (.videos, .loading): videosState = .loading
        case (.videos, .failed(let e)): videosState = .failed(e)
        }
    }
}

/// The cases of `SurfaceState` that carry no value, so they can be written into
/// any surface regardless of what that surface holds.
public enum ValuelessSurfaceState: Sendable {
    case idle
    case loading
    case failed(SolverError)
}

/// Enough of a `SurfaceState` to ask which case it is, without its value type.
///
/// The chain needs "is this surface idle?" across four differently-typed states;
/// a generic cannot express that and four switch arms in every caller is how the
/// blank-screen bug happened in the first place.
public struct AnySurfaceState: Sendable, Equatable {
    public let isIdle: Bool
    public let isLoading: Bool
    public let error: SolverError?
    public let hasValue: Bool

    init<T>(_ state: SurfaceState<T>) {
        isIdle = state.isIdle
        isLoading = state.isLoading
        error = state.error
        if case .ready = state { hasValue = true } else { hasValue = false }
    }
}

private extension Decodable {
    static var arrayType: [Self].Type { [Self].self }
}
