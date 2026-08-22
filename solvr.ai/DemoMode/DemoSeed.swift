import Foundation
import SwiftData
import SolvrCore

/// Populating screens that are empty on a fresh install, so a screenshot of
/// "History" shows history rather than an empty-state placeholder.
///
/// Only ever reached when demo mode is on. Every entry is synthetic: written for
/// this file, not taken from anyone's tutoring records.
enum DemoSeed {

    static let history: [(String, String)] = [
        ("Evaluate the definite integral of 3x^2 from 0 to 1", "CALCULUS \u{2022} INTEGRATION"),
        ("Solve 2x^2 - 5x - 3 = 0 by factoring", "ALGEBRA \u{2022} QUADRATICS"),
        ("Differentiate x^3 - 4x using the power rule", "CALCULUS \u{2022} DERIVATIVES"),
        ("One-sample t-test, n = 24, sample mean 51.2", "STATISTICS \u{2022} HYPOTHESIS TESTS"),
        ("Limit of sin(x)/x as x approaches 0", "CALCULUS \u{2022} LIMITS"),
    ]

    static func seedHistory(into context: ModelContext) {
        guard DemoMode.isEnabled else { return }
        let existing = (try? context.fetch(FetchDescriptor<Problem>())) ?? []
        guard existing.isEmpty else { return }

        for (offset, entry) in history.enumerated() {
            let created = Calendar.current.date(
                byAdding: .hour, value: -(offset * 7 + 1), to: .now) ?? .now
            context.insert(Problem(text: entry.0, topic: entry.1, createdAt: created))
        }
        try? context.save()
    }

    static let conversation: [ChatMessage] = [
        ChatMessage(role: .user, content: "Why does the constant of integration disappear here?"),
        ChatMessage(role: .assistant, content: DemoFixtures.chatReply),
    ]
}

extension ChatViewModel {

    func seedDemoConversation() {
        guard DemoMode.isEnabled, messages.isEmpty else { return }
        messages = DemoSeed.conversation
    }
}
