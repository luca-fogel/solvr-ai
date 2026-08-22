import Foundation

/// Everything that can go wrong between asking for a solution and having one.
///
/// This used to be `ClaudeAPIManager.ClaudeError`, nested inside the Anthropic
/// networking code. That nesting was load bearing in the wrong direction: four
/// SwiftUI views and the demo-fixture loader all named the Anthropic manager in
/// their type signatures, so the *demo* path -- which makes no network calls at
/// all -- could not compile without the HTTP client.
///
/// The cases are deliberately about what the user experiences rather than about
/// which backend produced them. A refused key, an exhausted context window and a
/// model that has not finished downloading are three different conversations to
/// have with someone, and only the first is anyone's fault.
public enum SolverError: LocalizedError, Equatable, Sendable {
    /// No credential is stored for a backend that needs one.
    case noAPIKey
    /// A credential exists and was rejected.
    case unauthorized
    case invalidResponse
    case apiError(String)
    case emptyResponse
    case networkUnavailable
    case timeout
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    /// The response arrived but could not be read as the shape we asked for.
    /// `context` carries "<surface>: <detail>" so the user sees the surface and
    /// the log keeps the detail.
    case decodingFailed(context: String)

    // The three below exist for backends that are not a hosted HTTP API.

    /// The selected backend cannot run here at all -- the device is not eligible,
    /// the feature is switched off, the local server is unreachable. `reason` is
    /// shown to the user, so it has to be a sentence rather than an enum name.
    case backendUnavailable(reason: String)
    /// The backend exists and will work, but not yet: an on-device model still
    /// downloading, or a Mac still waking. Distinct from `backendUnavailable`
    /// because the honest advice is "try again shortly" rather than "change this".
    case modelNotReady
    /// Prompt plus completion did not fit the model's context window. Worth its
    /// own case because the fix is ours, not the user's.
    case contextExceeded

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key found. Please add your API key in Settings."
        case .unauthorized:
            return "That API key was rejected. Please check your key in Settings."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .apiError(let message):
            return "API Error: \(message)"
        case .emptyResponse:
            return "Received an empty response."
        case .networkUnavailable:
            return "No internet connection. Please check your network and try again."
        case .timeout:
            return "The request timed out. Please try again."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case .decodingFailed(let context):
            let label = context.components(separatedBy: ":").first ?? context
            return "Could not parse \(label). The AI response was in an unexpected format. Try again."
        case .backendUnavailable(let reason):
            return reason
        case .modelNotReady:
            return "The model is still getting ready. Please try again in a moment."
        case .contextExceeded:
            return "This problem was too long for the selected model. Try a shorter problem, or switch backend in Settings."
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
        case .noAPIKey, .unauthorized: return "key.slash.fill"
        case .networkUnavailable: return "wifi.slash"
        case .timeout: return "clock.badge.exclamationmark"
        case .rateLimited: return "gauge.with.dots.needle.67percent"
        case .serverError: return "server.rack"
        case .decodingFailed: return "doc.questionmark.fill"
        case .backendUnavailable: return "cpu"
        case .modelNotReady: return "hourglass"
        case .contextExceeded: return "text.append"
        default: return "exclamationmark.triangle.fill"
        }
    }

    public var title: String {
        switch self {
        case .noAPIKey: return "API Key Missing"
        case .unauthorized: return "Invalid API Key"
        case .networkUnavailable: return "You're Offline"
        case .timeout: return "Request Timed Out"
        case .rateLimited: return "Too Many Requests"
        case .serverError: return "Server Error"
        case .decodingFailed: return "Parsing Error"
        case .invalidResponse: return "Invalid Response"
        case .apiError: return "API Error"
        case .emptyResponse: return "Empty Response"
        case .backendUnavailable: return "Backend Unavailable"
        case .modelNotReady: return "Model Not Ready"
        case .contextExceeded: return "Problem Too Long"
        }
    }
}
