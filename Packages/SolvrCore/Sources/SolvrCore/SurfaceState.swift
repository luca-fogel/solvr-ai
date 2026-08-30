import Foundation

/// Everything one tab of the results screen can be.
///
/// This exists because of a blank screen. Each result view was written as
/// `if isLoading … else if let error … else if let value` with no final `else`,
/// so the fourth combination -- not loading, no error, nothing to show -- drew
/// nothing at all, and all four views had it. Three booleans and an optional
/// describe sixteen states, of which four are real; an enum describes the four.
///
/// Making it a type rather than a convention means a view that forgets a case
/// does not compile. That matters more than it sounds: `idle` is a *new* state,
/// added when tabs stopped being fetched all at once, and it is now the state
/// most tabs are in most of the time.
public enum SurfaceState<Value: Sendable>: Sendable {

    /// Never asked for. The on-device model answers one thing at a time, so a
    /// tab is fetched when it is opened rather than up front.
    case idle

    /// Asked for, still generating.
    case loading

    /// Asked for, and the model or the device said no.
    case failed(SolverError)

    /// Answered, with nothing in it. Distinct from `failed`: nothing went
    /// wrong, the model simply returned an empty list.
    case empty

    /// Answered.
    case ready(Value)

    public var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }

    public var error: SolverError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Whether this surface has never been requested, which is what tells the
    /// screen it has to ask.
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

extension SurfaceState: Equatable where Value: Equatable {}
