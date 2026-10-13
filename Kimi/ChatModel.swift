import Foundation

/// The conversation: what is on screen, what is sent, what is kept on the phone.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var busy = false
    @Published var error: String?

    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chat.json")
    private let keep = 200

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    /// Returns the answer so the caller can read it aloud, or nil on failure (the error is shown instead).
    func send(_ text: String, voice: Bool) async -> String? {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return nil }
        error = nil
        busy = true
        defer { busy = false }
        messages.append(ChatMessage(role: .user, text: question))
        do {
            let answer = try await askKimi(history: messages, voice: voice)
            messages.append(ChatMessage(role: .assistant, text: answer))
            save()
            return answer
        } catch {
            // drop the unanswered question so roles keep alternating
            messages.removeLast()
            self.error = error.localizedDescription
            return nil
        }
    }

    func clear() {
        messages = []
        save()
    }

    private func save() {
        let recent = Array(messages.suffix(keep))
        if let data = try? JSONEncoder().encode(recent) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }
}
