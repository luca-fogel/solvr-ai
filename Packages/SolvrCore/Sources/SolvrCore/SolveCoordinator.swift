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

/// Owns one `Solve`: which surfaces have been asked for, and what came back.
///
/// The rule this type exists to enforce is in one line, `enqueue`'s first:
/// **every request is built from `solve.question`, and there is no other string
/// it could be built from.** The version this replaces read a mutable
/// `currentInput` that four different code paths could write, one of which wrote
/// the words on screen; a photograph of an integral therefore produced a lesson
/// about flatbed scanners, and nothing in the repository could have caught it,
/// because this logic lived in a view model in the app target and the app target
/// has no tests.
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

    /// What is being solved. `nil` means nothing is, and nothing can be asked.
    public private(set) var solve: Solve?

    /// The tail of the request chain.
    ///
    /// The on-device model serves one request at a time
    /// (`RequestQueue(maxConcurrent: 1)` inside the provider, and
    /// `GenerationError.concurrentRequests` behind that). Four detached tasks
    /// therefore did not run in parallel; they ran in whatever order the
    /// scheduler happened to start them, which is why Videos could fill in
    /// before the Steps tab the user was staring at. Each new request awaits the
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

    // MARK: - Begin

    /// Start on a problem. The `Solve` is already resolved -- if it came from a
    /// photograph, the photograph has already been read -- so there is nothing
    /// left to decide about what the model will be asked.
    public func begin(_ solve: Solve) {
        clear()
        self.solve = solve

        // Steps only. The other three surfaces are generated when their tab is
        // opened -- see `ensureLoaded`. On a device that answers one request at
        // a time, asking for four means the first answer arrives after one
        // generation and the last after four; most students never open Videos.
        enqueue(.steps)
    }

    /// Restore a saved solve, with whatever surfaces were saved alongside it.
    ///
    /// `solve` is `nil` for a history entry written before the app recorded what
    /// it read from a photograph. Those entries keep the surfaces that were
    /// saved and refuse to generate the ones that were not, because the only
    /// thing left to ask about is a display label -- and asking the model about
    /// a display label is the bug all of this exists to remove.
    public func restore(_ solve: Solve?,
                        stepsJSON: String?,
                        lessonJSON: String?,
                        formulasJSON: String?,
                        videosJSON: String?) {
        clear()
        self.solve = solve

        stepsState = Self.restore([StepItem].self, from: stepsJSON, whenAbsent: solve)
        lessonState = Self.restore(LessonContent.self, from: lessonJSON, whenAbsent: solve)
        formulasState = Self.restore([FormulaItem].self, from: formulasJSON, whenAbsent: solve)
        videosState = Self.restore([VideoItem].self, from: videosJSON, whenAbsent: solve)
    }

    /// Put every surface into the same failure, for something that went wrong
    /// before any request could be made.
    public func failEverything(with error: SolverError) {
        clear()
        stepsState = .failed(error)
        lessonState = .failed(error)
        formulasState = .failed(error)
        videosState = .failed(error)
    }

    /// Forget the current solve and everything in flight for it.
    public func clear() {
        solve = nil
        tail?.cancel()
        tail = nil
        stepsState = .idle
        lessonState = .idle
        formulasState = .idle
        videosState = .idle
    }

    // MARK: - Asking

    /// Fetch a surface the first time it is looked at.
    ///
    /// Idempotent: a surface that is loading, loaded or failed is left alone, so
    /// switching back and forth does not re-ask.
    public func ensureLoaded(_ surface: Surface) {
        guard state(for: surface).isIdle else { return }
        enqueue(surface)
    }

    /// A retry is a person waiting, so it goes to the front rather than behind
    /// whatever speculative surface is in flight.
    ///
    /// It does *not* cancel the tail any more. Cancelling it stranded whatever
    /// surface that task was going to fetch: the cancelled task returned before
    /// writing any state, so the tab it belonged to sat on a `loading` spinner
    /// for the life of the screen, with no error and no way out.
    public func retry(_ surface: Surface) {
        enqueue(surface)
    }

    private func enqueue(_ surface: Surface) {
        // The one line that matters: a request is built from the resolved
        // question or it is not made. There is no other string in scope here
        // that a prompt could be built from, which is the whole point of `Solve`.
        guard let solve else {
            set(surface, .failed(.nothingToSolve))
            return
        }
        let question = solve.question
        let id = solve.id
        set(surface, .loading)

        let previous = tail
        tail = Task { @MainActor [weak self] in
            // Wait for whatever was asked for first. Not cancelling it: a
            // cancelled generation returns nothing, so cancelling to jump the
            // queue throws away the seconds already spent on a surface the user
            // will probably still want.
            await previous?.value
            guard let self else { return }
            guard !Task.isCancelled else {
                // Never return without writing a terminal state. A surface left
                // on `loading` is a spinner nothing will ever stop.
                self.set(surface, .idle)
                return
            }
            await self.fetch(surface, question: question, id: id)
        }
    }

    private func fetch(_ surface: Surface, question: String, id: UUID) async {
        let provider = self.provider()
        do {
            switch surface {
            case .steps:
                let result = try await provider.steps(for: question)
                apply(id) { $0.stepsState = result.isEmpty ? .empty : .ready(result) }
            case .lesson:
                let result = try await provider.lesson(for: question)
                apply(id) { $0.lessonState = .ready(result) }
            case .formulas:
                let result = try await provider.formulas(for: question)
                apply(id) { $0.formulasState = result.isEmpty ? .empty : .ready(result) }
            case .videos:
                let result = try await provider.videos(for: question)
                apply(id) { $0.videosState = result.isEmpty ? .empty : .ready(result) }
            }
        } catch {
            let failure = (error as? SolverError) ?? .apiError(error.localizedDescription)
            apply(id) { $0.set(surface, .failed(failure)) }
        }
    }

    /// Write a result only if it belongs to the solve that is on screen.
    ///
    /// Backing out of a problem and solving another one used to leave the first
    /// solve's requests in flight, still writing their answers in when they
    /// finished -- so the answer to the previous question appeared under the new
    /// one, which looks exactly like a model that ignored the question.
    private func apply(_ id: UUID, _ change: (SolveCoordinator) -> Void) {
        guard solve?.id == id else { return }
        change(self)
    }

    private static func restore<T: Decodable & Sendable>(
        _ type: T.Type, from json: String?, whenAbsent solve: Solve?
    ) -> SurfaceState<T> {
        if let json, let data = json.data(using: .utf8),
           let value = try? JSONDecoder().decode(T.self, from: data) {
            return .ready(value)
        }
        // Nothing saved. If we know what the question was, this surface is
        // simply unasked; if we do not, say so rather than inventing one.
        return solve == nil ? .failed(.questionNotRecorded) : .idle
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

    /// Await everything this coordinator has in flight.
    ///
    /// Internal, for tests. The chain is a linked list of tasks each awaiting
    /// its predecessor, so awaiting the tail awaits all of them.
    func settle() async {
        await tail?.value
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
/// a generic cannot express that, and four switch arms in every caller is how
/// the blank-screen bug happened in the first place.
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
