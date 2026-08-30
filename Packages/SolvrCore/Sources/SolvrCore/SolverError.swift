import Foundation

/// Everything that can go wrong between asking for a solution and having one.
///
/// This used to be `ClaudeAPIManager.ClaudeError`, nested inside the Anthropic
/// networking code. That nesting was load bearing in the wrong direction: four
/// SwiftUI views and the demo-fixture loader all named the Anthropic manager in
/// their type signatures, so the *demo* path -- which makes no network calls at
/// all -- could not compile without the HTTP client.
///
/// Six HTTP-shaped cases were removed with the hosted backend: a missing key, a
/// rejected key, an empty body, no connection, a timeout, and a 5xx. None of them
/// can happen to a model running on the same silicon as the app, and every one of
/// them was unreachable once the last URLSession went. What is left describes
/// what the *user* experiences, which is the distinction that made this enum
/// worth extracting in the first place: a model that has not finished downloading
/// and an exhausted context window are two different conversations to have with
/// someone, and neither is their fault.
public enum SolverError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    /// A failure the framework reported that we have no better name for. Carries
    /// the underlying description so it is not lost.
    case apiError(String)
    /// The model refused concurrent work and wants to be asked again. On-device
    /// generation serialises, so this is a queueing signal rather than a quota.
    case rateLimited(retryAfter: TimeInterval?)
    /// The response arrived but could not be read as the shape we asked for.
    /// `context` carries "<surface>: <detail>" so the user sees the surface and
    /// the log keeps the detail.
    case decodingFailed(context: String)
    /// The model cannot run here at all -- the device is not eligible, or Apple
    /// Intelligence is switched off. `reason` is shown to the user, so it has to
    /// be a sentence rather than an enum name.
    case backendUnavailable(reason: String)
    /// The model exists and will work, but not yet: still downloading, or still
    /// being prepared by the system. Distinct from `backendUnavailable` because
    /// the honest advice is "try again shortly" rather than "change this".
    case modelNotReady
    /// Prompt plus completion did not fit the model's context window. Worth its
    /// own case because the fix is ours, not the user's.
    case contextExceeded
    /// There is no question to ask. Reachable from the "Generate" button on a
    /// surface that has never been given a problem, which used to send the model
    /// an empty string and present whatever came back.
    case nothingToSolve
    /// A saved problem from before the app recorded what it read from the
    /// photograph. The tabs that were saved with it are fine; the ones that were
    /// not cannot be filled in, because the only thing left is a label and a
    /// label is not a question. Asking the model about it anyway is exactly the
    /// bug this case exists to refuse.
    case questionNotRecorded

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The model returned something that could not be read."
        case .apiError(let message):
            return message
        case .rateLimited:
            return "The model is busy with another part of this problem. Try again in a moment."
        case .decodingFailed(let context):
            let label = context.components(separatedBy: ":").first ?? context
            return "Could not parse \(label). The response was in an unexpected format. Try again."
        case .backendUnavailable(let reason):
            return reason
        case .modelNotReady:
            return "The model is still getting ready. Please try again in a moment."
        case .contextExceeded:
            // Measured: this fires on six-word problems. The model's 4,096-token
            // window covers the prompt *and* the answer, so it is usually the
            // answer that ran long, not the question -- and telling a student to
            // shorten a question that was already short is advice they cannot
            // act on.
            return "The answer ran longer than the model could hold in memory. "
                 + "Try again, or ask for a smaller piece of the problem."
        case .nothingToSolve:
            return "There is no problem here to work on yet. Scan or type one first."
        case .questionNotRecorded:
            return "This one was saved before the app kept a record of what it "
                 + "read from the photo, so there is nothing to ask about. "
                 + "Scan it again to fill this tab in."
        }
    }

    /// Whether offering "Try again" would be honest.
    ///
    /// Two of these cases cannot be retried into success: there is no question,
    /// and no amount of asking again will produce one. A retry button that
    /// cannot work is worse than none, because it implies the failure was
    /// transient.
    public var isRetryable: Bool {
        switch self {
        case .nothingToSolve, .questionNotRecorded: return false
        default: return true
        }
    }

    /// The half of `decodingFailed`'s context that belongs in a log rather than
    /// on screen.
    public var debugDetail: String? {
        switch self {
        case .decodingFailed(let context) where context.contains(":"):
            return String(context.dropFirst((context.components(separatedBy: ":").first?.count ?? 0) + 2))
        case .apiError(let message):
            return message
        default:
            return nil
        }
    }

    public var icon: String {
        switch self {
        case .rateLimited: return "gauge.with.dots.needle.67percent"
        case .decodingFailed: return "doc.questionmark.fill"
        case .backendUnavailable: return "cpu"
        case .modelNotReady: return "hourglass"
        case .contextExceeded: return "text.append"
        case .nothingToSolve: return "questionmark.square.dashed"
        case .questionNotRecorded: return "text.viewfinder"
        default: return "exclamationmark.triangle.fill"
        }
    }

    public var title: String {
        switch self {
        case .invalidResponse: return "Unreadable Response"
        case .apiError: return "Something Went Wrong"
        case .rateLimited: return "Model Busy"
        case .decodingFailed: return "Parsing Error"
        case .backendUnavailable: return "Model Unavailable"
        case .modelNotReady: return "Model Not Ready"
        case .contextExceeded: return "Ran Out of Room"
        case .nothingToSolve: return "Nothing To Solve"
        case .questionNotRecorded: return "Not Recorded"
        }
    }
}
