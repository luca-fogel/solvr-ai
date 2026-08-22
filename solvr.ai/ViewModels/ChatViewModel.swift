import SwiftUI
import SolvrCore

@Observable
final class ChatViewModel {
    
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: SolverError?
    
    private var problemContext: String = ""
    private let api = ClaudeAPIManager.shared
    
    let suggestedPrompts = [
        "Explain step 3 more",
        "Give me a similar practice problem",
        "Why does this formula work?",
        "What if the numbers were different?"
    ]
    
    func setProblemContext(_ problem: String) {
        problemContext = problem
    }
    
    func sendMessage(_ text: String? = nil) async {
        let content = (text ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: content)
        
        await MainActor.run {
            messages.append(userMessage)
            inputText = ""
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let response = try await api.sendChatMessage(
                content,
                problemContext: problemContext,
                history: messages.filter { $0.role != .user || $0.id != userMessage.id }
            )
            
            let assistantMessage = ChatMessage(role: .assistant, content: response)
            await MainActor.run {
                messages.append(assistantMessage)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = (error as? SolverError) ?? .apiError(error.localizedDescription)
                isLoading = false
            }
        }
    }
    
    func clear() {
        messages.removeAll()
        inputText = ""
        errorMessage = nil
    }

    func saveMessages(to problem: Problem) {
        guard !messages.isEmpty else { return }
        if let data = try? JSONEncoder().encode(messages),
           let json = String(data: data, encoding: .utf8) {
            problem.chatMessagesJSON = json
        }
    }

    func loadMessages(from problem: Problem) {
        guard let json = problem.chatMessagesJSON,
              let data = json.data(using: .utf8),
              let loaded = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return
        }
        messages = loaded
    }
}
