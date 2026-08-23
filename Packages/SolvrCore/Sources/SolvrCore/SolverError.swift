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
            return "This problem was too long for the on-device model. Try a shorter problem."
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
        case .contextExceeded: return "Problem Too Long"
        }
    }
}
