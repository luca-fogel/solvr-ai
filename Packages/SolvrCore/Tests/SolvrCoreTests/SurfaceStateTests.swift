import Testing
import Foundation
@testable import SolvrCore

/// The states a results tab can be in. Four of them, exhaustively, because the
/// version that used three booleans and an optional had a combination nobody
/// wrote a branch for and it drew a blank screen.
@Suite("Surface state")
struct SurfaceStateTests {

    @Test("each state reports itself and nothing else")
    func accessors() {
        let idle = SurfaceState<[Int]>.idle
        #expect(idle.isIdle)
        #expect(!idle.isLoading)
        #expect(idle.value == nil)
        #expect(idle.error == nil)

        let loading = SurfaceState<[Int]>.loading
        #expect(loading.isLoading)
        #expect(!loading.isIdle)

        let failed = SurfaceState<[Int]>.failed(.modelNotReady)
        #expect(failed.error == .modelNotReady)
        #expect(failed.value == nil)

        let empty = SurfaceState<[Int]>.empty
        #expect(empty.value == nil)
        #expect(empty.error == nil)
        #expect(!empty.isIdle)   // asked, and answered with nothing

        let ready = SurfaceState.ready([1, 2, 3])
        #expect(ready.value == [1, 2, 3])
        #expect(!ready.isLoading)
    }

    @Test("empty is not idle, because the difference is what the screen says")
    func emptyIsNotIdle() {
        #expect(!SurfaceState<[Int]>.empty.isIdle)
        #expect(SurfaceState<[Int]>.idle.isIdle)
    }

    /// Verbatim from an iOS 26.4 simulator, which reports the model available
    /// and then fails every request with this.
    @Test("an unrecognised framework failure is explained, not quoted")
    func unrecognisedFailureIsExplained() {
        let raw = "The operation couldn’t be completed. "
            + "(FoundationModels.LanguageModelSession.GenerationError error -1.)"
        let error = SolverError.apiError(raw)
        #expect(error.errorDescription?.contains("FoundationModels") == false)
        #expect(error.errorDescription?.contains("Apple Intelligence") == true)
        #expect(error.debugDetail == raw)   // kept, in the small print
        #expect(error.isRetryable)
    }
}
