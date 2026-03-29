import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = .now
    }

    enum ChatRole: String, Equatable, Codable {
        case user
        case assistant
    }
}
