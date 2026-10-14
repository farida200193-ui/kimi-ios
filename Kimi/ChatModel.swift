import Foundation

/// The conversation: what is on screen, what is sent, what is kept on the phone.
/// Kimy works as an agent: reads from connected apps by itself, stops before acting until the owner approves.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var busy = false
    @Published private(set) var pending: Agent.Action?   // waits for «Выполнить» / «Отмена»
    @Published var error: String?

    private let connectors = Connectors.shared
    private let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chat.json")
    private let keep = 200
    private let maxSteps = 6   // reads in a row before Kimy must answer

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    var visible: [ChatMessage] {
        messages.filter { $0.hidden != true && !($0.role == .assistant && Agent.clean($0.text).isEmpty) }
    }

    /// Returns the answer so the caller can read it aloud, or nil on failure (the error is shown instead).
    func send(_ text: String, voice: Bool) async -> String? {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return nil }
        if pending != nil { decline() }
        messages.append(ChatMessage(role: .user, text: question))
        return await work(voice: voice)
    }

    func approve(voice: Bool = false) async -> String? {
        guard let action = pending, !busy else { return nil }
        pending = nil
        let result = await connectors.run(action)
        messages.append(ChatMessage(role: .user, text: "Результат \(action.tool) (владелец подтвердил): \(result)", hidden: true))
        return await work(voice: voice)
    }

    func decline() {
        guard let action = pending else { return }
        pending = nil
        connectors.log(Agent.describe(action), status: "отменено")
        messages.append(ChatMessage(role: .user, text: "Владелец отменил действие \(action.tool).", hidden: true))
        messages.append(ChatMessage(role: .assistant, text: "Хорошо, не делаю."))
        save()
    }

    /// Ask the model, run what it may run, repeat until it answers or needs the owner.
    private func work(voice: Bool) async -> String? {
        error = nil
        busy = true
        defer { busy = false }
        let start = messages.count
        do {
            for _ in 0..<maxSteps {
                let raw = try await askKimi(history: messages, voice: voice, context: connectors.context())
                let reply = Agent.parse(raw)
                connectors.forget(numbers: reply.forget)
                connectors.remember(reply.remember)
                messages.append(ChatMessage(role: .assistant, text: raw))
                guard let action = reply.actions.first else {
                    save()
                    return reply.text
                }
                switch connectors.gate(action) {
                case .run:
                    let result = await connectors.run(action)
                    messages.append(ChatMessage(role: .user, text: "Результат \(action.tool): \(result)", hidden: true))
                case .ask:
                    pending = action
                    save()
                    return reply.text.isEmpty ? "Нужно ваше подтверждение." : reply.text + " Нужно ваше подтверждение."
                case let .refuse(why):
                    connectors.log(Agent.describe(action), status: "не разрешено")
                    messages.append(ChatMessage(role: .user, text: "Не выполнено: \(why)", hidden: true))
                }
            }
            messages.append(ChatMessage(role: .assistant, text: "Остановился: слишком много шагов подряд. Уточните задачу."))
            save()
            return nil
        } catch {
            // drop what this turn added (and the unanswered question) so roles keep alternating
            let drop = messages.count - start + (messages[safe: start - 1]?.role == .user && messages[safe: start - 1]?.hidden != true ? 1 : 0)
            messages.removeLast(min(drop, messages.count))
            self.error = error.localizedDescription
            return nil
        }
    }

    func clear() {
        messages = []
        pending = nil
        save()
    }

    private func save() {
        var recent = Array(messages.suffix(keep))
        while recent.first?.hidden == true { recent.removeFirst() }
        if let data = try? JSONEncoder().encode(recent) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
