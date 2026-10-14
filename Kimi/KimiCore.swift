import Foundation

/// One line of the conversation. Stored on the phone between launches.
struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    let text: String
    var hidden: Bool? = nil   // action results for the model; not shown in the chat
    var files: [String]? = nil       // names of attached files, shown under the question
    var attachment: String? = nil    // their text, sent to the model with the question

    var forModel: String { attachment.map { $0 + "\n\n" + text } ?? text }
}

/// Request building and reply parsing. Foundation only, so it is tested without a phone (Tests/main.swift).
enum KimiCore {
    static let endpoint = URL(string: "https://api.timeweb.ai/v1/chat/completions")!
    static let defaultModel = "anthropic/claude-sonnet-5-5"
    // shortcut: older messages are silently dropped, upgrade to summarising when chats get long
    static let maxHistory = 20
    static let system = "Тебя зовут Kimy (по-русски — Кими), ты личный ассистент. Отвечай кратко и по делу, на языке пользователя. "
        + "У владельца есть ИИ-офис с сотрудниками (директор, ассистент, маркетолог, юрист, бухгалтер, отчёты и почта и другие). "
        + "Поручения сотрудникам и решения по их предложениям — на экране «Офис»: кнопка с домиком вверху или фраза «открой офис». "
        + "Если коннектор «Офис» не подключён, сам ты в офис не пишешь и не притворяешься, что передал поручение."
    // shortcut: a file is cut to this many characters, upgrade to chunking + summaries for big archives
    static let maxFileText = 60_000
    static let reportHint = "Вам прислали файлы — делайте выводы только по ним, цифры берите из файла. Если просят отчёт: заголовок, краткие итоги, ключевые цифры, выводы и рекомендации."

    /// Attached files as one block the model reads before the question.
    static func attachment(_ files: [(name: String, text: String)]) -> String? {
        guard !files.isEmpty else { return nil }
        let budget = maxFileText / files.count
        return files.map { f in
            let body = f.text.count > budget ? String(f.text.prefix(budget)) + "\n…[обрезано: файл длиннее \(budget) символов]" : f.text
            return "Файл «\(f.name)»:\n<<<\n\(body)\n>>>"
        }.joined(separator: "\n\n") + "\n" + reportHint
    }

    static let voiceHint = " Сейчас ответ будет зачитан вслух: говори коротко, живым языком, без списков и разметки."

    enum Failure: LocalizedError, Equatable {
        case noKey
        case emptyReply
        case service(Int, String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "Укажите ключ AI Gateway в настройках."
            case .emptyReply: return "Сервис вернул пустой ответ."
            case let .service(code, text): return "Сервис ответил \(code): \(text)"
            }
        }
    }

    /// The last messages, never opening with an assistant line (the model expects the user to speak first).
    static func recent(_ history: [ChatMessage]) -> [ChatMessage] {
        Array(history.suffix(maxHistory).drop(while: { $0.role == .assistant }))
    }

    static func requestBody(model: String, history: [ChatMessage], voice: Bool, context: String = "") throws -> Data {
        var messages: [[String: String]] = [["role": "system", "content": system + context + (voice ? voiceHint : "")]]
        messages += recent(history).map { ["role": $0.role.rawValue, "content": $0.forModel] }
        return try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])
    }

    static func parseReply(_ data: Data) throws -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let text = (message["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { throw Failure.emptyReply }
        return text
    }

    static func errorText(_ data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }

    /// «Открой офис», «покажи офис», «офис» — открывается экран офиса, вопрос в нейросеть не уходит.
    static func opensOffice(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t == "офис" || ["открой офис", "открыть офис", "покажи офис", "зайди в офис", "открой мой офис"].contains(t)
    }
    static func request(key: String, model: String, history: [ChatMessage], voice: Bool, context: String = "") throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Failure.noKey }
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(model: model, history: history, voice: voice, context: context)
        return request
    }
}

/// The owner's AI office on the server (kimi_api.py behind https://ai.edu-upgrade.ru/office/). Foundation only: tested in Tests/main.swift.
enum Office {
    static let base = URL(string: "https://ai.edu-upgrade.ru/office")!

    struct Reply: Equatable { let who: String; let text: String }
    struct Proposal: Equatable, Identifiable { let id: Int; let text: String }

    enum Failure: LocalizedError, Equatable {
        case noKey
        case server(Int, String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Впишите ключ входа в Офис в настройках."
            case let .server(code, text): return text.isEmpty ? "Офис ответил \(code)" : text
            }
        }
    }

    static func request(_ path: String, token: String, body: [String: Any]? = nil) throws -> URLRequest {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw Failure.noKey }
        // a discussion of several agents takes a while
        var r = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: path == "ask" ? 300 : 60)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    static func ask(_ text: String, token: String) throws -> URLRequest {
        try request("ask", token: token, body: ["text": text])
    }

    /// The code word goes only with an approval; a rejection needs none.
    static func decide(_ id: Int, approve: Bool, codeword: String, token: String) throws -> URLRequest {
        var body: [String: Any] = ["id": id, "decision": approve ? "approve" : "reject", "confirmed": true]
        if approve { body["codeword"] = codeword }
        return try request("decide", token: token, body: body)
    }

    static func check(_ data: Data, _ code: Int) throws -> [String: Any] {
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(code) else { throw Failure.server(code, root["error"] as? String ?? "") }
        return root
    }

    static func replies(_ root: [String: Any]) -> [Reply] {
        ((root["replies"] as? [[String: Any]]) ?? []).compactMap {
            guard let who = $0["who"] as? String, let text = $0["text"] as? String else { return nil }
            return Reply(who: who, text: text)
        }
    }

    static func proposals(_ root: [String: Any]) -> [Proposal] {
        ((root["proposals"] as? [[String: Any]]) ?? []).compactMap {
            guard let id = $0["id"] as? Int, let text = $0["text"] as? String else { return nil }
            return Proposal(id: id, text: text)
        }
    }
}

/// Personal voices of Kimy and the office team: Yandex SpeechKit (API v3), the owner's own API key.
enum SpeechKit {
    static let endpoint = URL(string: "https://tts.api.cloud.yandex.net/tts/v3/utteranceSynthesis")!
    static let maxText = 1500

    struct Voice: Equatable {
        let name: String
        let role: String?
        let speed: Double
    }

    static let kimy = Voice(name: "dasha", role: "friendly", speed: 1.05)
    /// The voice sheet from the design (board «Команда и голоса»).
    static let team: [String: Voice] = [
        "Майкл": Voice(name: "alexander", role: "good", speed: 1.15), "Эрин": Voice(name: "lera", role: "friendly", speed: 1.1),
        "Джим": Voice(name: "anton", role: "good", speed: 1.0), "Пэм": Voice(name: "masha", role: "friendly", speed: 1.0),
        "Филлис": Voice(name: "marina", role: "friendly", speed: 0.9), "Келли": Voice(name: "jane", role: "good", speed: 1.2),
        "Дуайт": Voice(name: "kirill", role: "strict", speed: 1.1), "Анджела": Voice(name: "julia", role: "strict", speed: 0.9),
        "Оскар": Voice(name: "ermil", role: "neutral", speed: 1.0), "Тоби": Voice(name: "zahar", role: "neutral", speed: 0.85),
        "Райан": Voice(name: "filipp", role: nil, speed: 1.15), "Программист": Voice(name: "madi_ru", role: nil, speed: 1.0),
        "Вера": Voice(name: "jane", role: "neutral", speed: 1.0), "Лев": Voice(name: "ermil", role: "good", speed: 0.95),
        "Макс": Voice(name: "kirill", role: "good", speed: 1.15), "Ева": Voice(name: "omazh", role: "neutral", speed: 0.95),
    ]

    /// "Майкл · директор" → Майкл's voice; anyone unknown speaks as Kimy.
    static func voice(for who: String) -> Voice {
        let name = who.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return team[name] ?? kimy
    }

    /// Markdown marks would be read aloud as symbols.
    static func speakable(_ text: String) -> String {
        var t = text
        for mark in ["**", "__", "`", "#", "*"] { t = t.replacingOccurrences(of: mark, with: "") }
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxText))
    }

    static func request(_ text: String, voice: Voice, key: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw KimiCore.Failure.noKey }
        var hints: [[String: Any]] = [["voice": voice.name], ["speed": voice.speed]]
        if let role = voice.role { hints.append(["role": role]) }
        let body: [String: Any] = ["text": speakable(text), "hints": hints, "unsafeMode": true,   // unsafeMode: texts longer than 250 characters
                                   "outputAudioSpec": ["containerAudio": ["containerAudioType": "MP3"]]]
        var r = URLRequest(url: endpoint, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("Api-Key \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// The answer is a stream of JSON lines, each with a piece of the MP3.
    static func audio(_ data: Data) -> Data {
        var out = Data()
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let result = root["result"] as? [String: Any],
                  let chunk = result["audioChunk"] as? [String: Any],
                  let b64 = chunk["data"] as? String,
                  let piece = Data(base64Encoded: b64) else { continue }
            out.append(piece)
        }
        return out
    }
}
