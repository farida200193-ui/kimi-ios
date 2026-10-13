import AppIntents

/// «Привет, Siri, спроси Кими» (iOS 16 and later). One question, one spoken answer; the chat on screen is not touched.
@available(iOS 16.0, *)
struct AskKimiIntent: AppIntent {
    static var title: LocalizedStringResource = "Спросить Kimy"
    static var description = IntentDescription("Задать Kimy вопрос и услышать ответ.")

    @Parameter(title: "Вопрос", requestValueDialog: "Что спросить у Кими?")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let answer = try await askKimi(history: [ChatMessage(role: .user, text: question)], voice: true)
            return .result(dialog: IntentDialog(stringLiteral: answer))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        }
    }
}

@available(iOS 16.0, *)
struct KimiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskKimiIntent(), phrases: ["Спроси \(.applicationName)", "Спросить \(.applicationName)"])
    }
}
