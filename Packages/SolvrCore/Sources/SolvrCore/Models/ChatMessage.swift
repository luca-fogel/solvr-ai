import Foundation

/// One turn of the follow-up conversation about a problem.
public struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let timestamp: Date

    public init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }

    /// No `system` case on purpose: system framing is the provider's business,
    /// not part of the conversation the user can see or the app persists.
    public enum ChatRole: String, Equatable, Codable, Sendable {
        case user
        case assistant
    }
}
