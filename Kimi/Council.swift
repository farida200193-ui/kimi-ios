import Foundation

/// «Идея»: seven AI advisors roast the owner's idea around the fire — the chairman asks, they argue, score, give a verdict.
/// Advisors are roles, not real people. Foundation only, tested in Tests/main.swift.
enum Council {
    struct Advisor: Equatable { let name: String; let focus: String }

    static let advisors = [
        Advisor(name: "Стратег", focus: "стратегия"),
        Advisor(name: "Финансист", focus: "деньги и риск"),
        Advisor(name: "Офферщик", focus: "офферы и цены"),
        Advisor(name: "Операционщик", focus: "операционка"),
        Advisor(name: "Продуктолог", focus: "продукт"),
        Advisor(name: "Маркетолог", focus: "внимание и бренд"),
        Advisor(name: "Кадровик", focus: "люди и время"),
    ]

    struct Line: Equatable { let who: String; let say: String }
    struct Score: Equatable { let who: String; let score: Int; let why: String }
    struct Result: Equatable {
        let debate: [Line]
        let scores: [Score]
        let ruin: Double
        let conditions: [String]
        var average: Double { scores.isEmpty ? 0 : Double(scores.map(\.score).reduce(0, +)) / Double(scores.count) }
    }

    private static var roster: String { advisors.map { "\($0.name) — \($0.focus)" }.joined(separator: "; ") }

    static func questionsPrompt(_ idea: String) -> String {
        "Ты председатель совета из семи советников (\(roster)). Владелец принёс идею: «\(idea)». "
            + "Задай ровно 3 коротких уточняющих вопроса, без которых совет не сможет оценить идею (обычно бюджет, сроки, что уже пробовали). "
            + #"Ответь только JSON без пояснений: {"questions":["…","…","…"]}"#
    }

    static func councilPrompt(_ idea: String, answers: [(q: String, a: String)]) -> String {
        let qa = answers.map { "— \($0.q) \($0.a.isEmpty ? "(не ответил)" : $0.a)" }.joined(separator: "\n")
        return "Совет разносит идею владельца. Советники: \(roster). Каждый смотрит только со своей стороны.\n"
            + "Идея: «\(idea)».\nОтветы владельца председателю:\n\(qa)\n"
            + "Говорите честно и жёстко, без воды, по-русски, конкретно про эту идею: цифры, риски, что сделать иначе. Советники спорят и возражают друг другу.\n"
            + #"Ответь только JSON без пояснений: {"debate":[{"who":"имя советника","say":"реплика до 200 символов"}], "#
            + #""scores":[{"who":"имя советника","score":0,"why":"одна фраза"}], "ruin":0, "conditions":["…"]}. "#
            + "debate — 8–12 реплик; scores — все семь, оценка 0–10; ruin — риск потерять деньги 0–10; conditions — до 4 условий, при которых идею стоит делать."
    }

    /// The model may wrap JSON in text or ```json fences: take the outermost object.
    static func json(_ text: String) -> [String: Any]? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[a...b].utf8)) as? [String: Any]
    }

    static func questions(_ text: String) -> [String] {
        ((json(text)?["questions"] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(3).map { $0 }
    }

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    static func result(_ text: String) -> Result? {
        guard let root = json(text) else { return nil }
        let debate: [Line] = ((root["debate"] as? [[String: Any]]) ?? []).compactMap {
            guard let who = $0["who"] as? String, let say = $0["say"] as? String, !say.isEmpty else { return nil }
            return Line(who: who, say: say)
        }
        let scores: [Score] = ((root["scores"] as? [[String: Any]]) ?? []).compactMap {
            guard let who = $0["who"] as? String, let s = number($0["score"]) else { return nil }
            return Score(who: who, score: min(max(Int(s.rounded()), 0), 10), why: $0["why"] as? String ?? "")
        }
        guard !scores.isEmpty else { return nil }
        let conditions = ((root["conditions"] as? [Any]) ?? []).compactMap { $0 as? String }
        return Result(debate: debate, scores: scores, ruin: min(max(number(root["ruin"]) ?? 0, 0), 10), conditions: Array(conditions.prefix(4)))
    }

    static func verdict(_ average: Double) -> String {
        average < 4.5 ? "НЕ ДЕЛАТЬ" : average < 7 ? "ДЕЛАТЬ С УСЛОВИЯМИ" : "ДЕЛАТЬ"
    }

    /// «5,0» — the Russian decimal comma, as on the verdict card.
    static func format(_ x: Double) -> String { String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",") }

    /// Text of the PDF report.
    static func report(idea: String, answers: [(q: String, a: String)], result r: Result) -> String {
        var lines = ["**Совет по идее:** \(idea)", "", "**Вердикт \(format(r.average))/10 — \(verdict(r.average).lowercased())**",
                     "Риск разорения: \(format(r.ruin)) из 10", ""]
        lines += r.scores.map { "\($0.who): \($0.score)/10 — \($0.why)" }
        if !r.conditions.isEmpty { lines += ["", "**Условия:**"] + r.conditions.map { "• \($0)" } }
        if !answers.isEmpty { lines += ["", "**Вопросы председателя:**"] + answers.map { "\($0.q) — \($0.a.isEmpty ? "без ответа" : $0.a)" } }
        lines += ["", "**Спор:**"] + r.debate.map { "\($0.who): \($0.say)" }
        return lines.joined(separator: "\n")
    }
}
