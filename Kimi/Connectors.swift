import Foundation
import EventKit
import Contacts
import UIKit

/// The owner's connected apps, what Kimy remembers, and the journal of everything Kimy did (Muse's audit trail).
/// Settings live in UserDefaults, memory and journal in protected files, MCP tokens in the Keychain.
@MainActor
final class Connectors: ObservableObject {
    static let shared = Connectors()

    struct Server: Codable, Identifiable, Equatable {
        var id: String { name }
        let name: String
        let url: String
    }

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let text: String
        let status: String   // выполнено, отменено, ошибка, не разрешено
    }

    @Published private(set) var access: [String: Agent.Access] = [:]
    @Published private(set) var servers: [Server] = []
    @Published private(set) var mcpTools: [String: [Agent.RemoteTool]] = [:]
    @Published private(set) var memory: [String] = []
    @Published private(set) var journal: [Entry] = []

    private let events = EKEventStore()
    private let defaults = UserDefaults.standard
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private init() {
        access = load("access", from: defaults) ?? [:]
        servers = load("servers", from: defaults) ?? []
        mcpTools = load("mcpTools", from: defaults) ?? [:]
        memory = loadFile("memory.json") ?? []
        journal = loadFile("journal.json") ?? []
        officeKeyChanged()
    }

    /// The Office is the owner's own server: with its key in place Kimy may ask it, unless the owner switched it off.
    func officeKeyChanged() {
        let hasKey = !Keychain.read(Keychain.office).isEmpty
        if hasKey && access["office"] == nil { access["office"] = .read }
        if !hasKey && access["office"] != nil { access["office"] = nil }
        store(access, "access")
    }

    var mcpAccess: [String: Agent.Access] {
        Dictionary(uniqueKeysWithValues: servers.map { ($0.name, access["mcp:" + $0.name] ?? .off) })
    }

    var connectedCount: Int { access.values.filter { $0 != .off }.count }

    func context() -> String {
        Agent.context(access: access, mcp: mcpTools, mcpAccess: mcpAccess, memory: memory, now: Date())
    }

    func gate(_ action: Agent.Action) -> Agent.Gate {
        Agent.gate(action, access: access, mcp: mcpTools, mcpAccess: mcpAccess)
    }

    // MARK: access levels

    /// Switching a connector on asks iOS for the permission it needs. Returns a problem to show, or nil.
    func set(_ id: String, _ level: Agent.Access) async -> String? {
        if level != .off {
            switch id {
            case "calendar": if !(await allow(.event)) { return "Разрешите Kimy доступ к календарю: Настройки → Kimy → Календари." }
            case "reminders": if !(await allow(.reminder)) { return "Разрешите Kimy доступ к напоминаниям: Настройки → Kimy → Напоминания." }
            case "contacts":
                if !((try? await CNContactStore().requestAccess(for: .contacts)) ?? false) { return "Разрешите Kimy доступ к контактам: Настройки → Kimy → Контакты." }
            case "health": if let problem = await Fitness.shared.authorize() { return problem }
            case "office": if Keychain.read(Keychain.office).isEmpty { return "Сначала впишите ключ Офиса в настройках." }
            default: break
            }
        }
        access[id] = level
        store(access, "access")
        log("\(title(id)): \(label(level))", status: "настройка")
        return nil
    }

    func title(_ id: String) -> String {
        id.hasPrefix("mcp:") ? String(id.dropFirst(4)) : Agent.connector(id)?.title ?? id
    }

    func label(_ level: Agent.Access) -> String {
        switch level {
        case .off: return "выключено"
        case .read: return "только чтение"
        case .act: return "чтение и действия"
        }
    }

    private func allow(_ type: EKEntityType) async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await (type == .event ? events.requestFullAccessToEvents() : events.requestFullAccessToReminders())) ?? false
        }
        return await withCheckedContinuation { c in events.requestAccess(to: type) { ok, _ in c.resume(returning: ok) } }
    }

    // MARK: memory and journal

    func remember(_ facts: [String]) {
        for f in facts where !memory.contains(f) { memory.append(String(f.prefix(300))) }
        saveFile(memory, "memory.json")
    }

    /// Numbers as the model saw them (1-based).
    func forget(numbers: [Int]) {
        let drop = Set(numbers.map { $0 - 1 })
        memory = memory.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        saveFile(memory, "memory.json")
    }

    func forget(at offsets: IndexSet) {
        memory = memory.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        saveFile(memory, "memory.json")
    }

    func forgetAll() {
        memory = []
        saveFile(memory, "memory.json")
    }

    func log(_ text: String, status: String) {
        journal.insert(Entry(date: Date(), text: text, status: status), at: 0)
        journal = Array(journal.prefix(300))
        saveFile(journal, "journal.json")
    }

    // MARK: doing things

    /// Runs an allowed action and returns the text the model gets back. Never throws: errors go back to the model too.
    func run(_ a: Agent.Action) async -> String {
        do {
            let result = try await perform(a)
            log(Agent.describe(a), status: "выполнено")
            return String(result.prefix(6000))
        } catch {
            log(Agent.describe(a), status: "ошибка")
            return "Ошибка: \(error.localizedDescription)"
        }
    }

    struct Problem: LocalizedError { let errorDescription: String? }

    private func perform(_ a: Agent.Action) async throws -> String {
        let x = a.args
        switch a.tool {
        case "calendar.list":
            let from = Agent.date(x["from"]) ?? Calendar.current.startOfDay(for: Date())
            let days = min(max(Int(x["days"] ?? "1") ?? 1, 1), 31)
            let to = Calendar.current.date(byAdding: .day, value: days, to: from) ?? from
            let found = events.events(matching: events.predicateForEvents(withStart: from, end: to, calendars: nil))
            if found.isEmpty { return "Событий нет." }
            return found.prefix(60).map { e in
                let time = e.isAllDay ? "весь день" : "\(Self.time.string(from: e.startDate))–\(Self.time.string(from: e.endDate))"
                return "\(Self.day.string(from: e.startDate)) \(time) \(e.title ?? "")" + ((e.location ?? "").isEmpty ? "" : " (\(e.location!))")
            }.joined(separator: "\n")

        case "calendar.add":
            guard let start = Agent.date(x["start"]) else { throw Problem(errorDescription: "Не понял время начала.") }
            let e = EKEvent(eventStore: events)
            e.title = x["title"] ?? "Событие"
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double(Int(x["minutes"] ?? "60") ?? 60) * 60)
            e.location = x["place"]
            e.calendar = events.defaultCalendarForNewEvents
            try events.save(e, span: .thisEvent)
            return "Событие создано."

        case "calendar.series":
            guard let start = Agent.date(x["start"]) else { throw Problem(errorDescription: "Не понял время первой тренировки.") }
            let e = EKEvent(eventStore: events)
            e.title = x["title"] ?? "Тренировка"
            e.notes = x["notes"]
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double(Int(x["minutes"] ?? "45") ?? 45) * 60)
            e.calendar = events.defaultCalendarForNewEvents
            let weeks = min(max(Int(x["weeks"] ?? "4") ?? 4, 1), 26)
            let days = Agent.weekdays(x["days"] ?? "").compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
            e.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: days.isEmpty ? .daily : .weekly, interval: 1, daysOfTheWeek: days.isEmpty ? nil : days,
                                                 daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
                                                 end: EKRecurrenceEnd(end: start.addingTimeInterval(Double(weeks) * 7 * 86400))))
            e.addAlarm(EKAlarm(relativeOffset: -15 * 60))
            try events.save(e, span: .futureEvents)
            return "Тренировки поставлены в календарь на \(weeks) нед., напоминание за 15 минут."

        case "health.steps":
            return try await Fitness.shared.report(days: Int(x["days"] ?? "7") ?? 7)
        case "health.summary":
            return await Fitness.shared.summary()
        case "steps.goal":
            guard let n = Int((x["steps"] ?? "").filter(\.isNumber)) else { throw Problem(errorDescription: "Не понял цель по шагам.") }
            return try await Fitness.shared.setGoal(n)

        case "reminders.list":
            let predicate = events.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            let items: [EKReminder] = await withCheckedContinuation { c in events.fetchReminders(matching: predicate) { c.resume(returning: $0 ?? []) } }
            if items.isEmpty { return "Невыполненных напоминаний нет." }
            return items.prefix(60).map { r in
                let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { " — до \(Self.day.string(from: $0)) \(Self.time.string(from: $0))" } ?? ""
                return "• \(r.title ?? "")\(due)"
            }.joined(separator: "\n")

        case "reminders.add":
            let r = EKReminder(eventStore: events)
            r.title = x["title"] ?? "Напоминание"
            r.calendar = events.defaultCalendarForNewReminders()
            if let due = Agent.date(x["due"]) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                r.addAlarm(EKAlarm(absoluteDate: due))
            }
            try events.save(r, commit: true)
            return "Напоминание создано."

        case "contacts.find":
            let name = (x["name"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw Problem(errorDescription: "Не указано имя.") }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
            let found = try CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
            if found.isEmpty { return "Контакт не найден." }
            return found.prefix(10).map { c in
                let phones = c.phoneNumbers.map(\.value.stringValue), mails = c.emailAddresses.map { $0.value as String }
                return "\(c.givenName) \(c.familyName): " + (phones + mails).joined(separator: ", ")
            }.joined(separator: "\n")

        case "message.send":
            return try await open(Agent.messageURL(x), "\(Agent.appName(x["app"])) открыт с готовым текстом, владелец отправит сам.")
        case "shortcut.run":
            return try await open(Agent.shortcutURL(x["name"] ?? "", input: x["input"]), "Команда запущена.")
        case "maps.route":
            return try await open(Agent.mapsURL(x["to"] ?? ""), "Маршрут открыт в Картах.")

        case "office.ask":
            let root = try await callOffice { try Office.ask(x["text"] ?? "", token: $0) }
            let replies = Office.replies(root)
            return replies.isEmpty ? "Поручение передано, ответ придёт в Telegram-группу офиса." : replies.map { "\($0.who): \($0.text)" }.joined(separator: "\n\n")

        case "office.proposals":
            let list = Office.proposals(try await callOffice { try Office.request("proposals", token: $0) })
            return list.isEmpty ? "Решений не ждёт ничего." : list.map { "№\($0.id): \($0.text)" }.joined(separator: "\n")

        case "mcp":
            guard let name = x["server"], let server = servers.first(where: { $0.name == name }), let tool = x["tool"] else {
                throw Problem(errorDescription: "Сервер не подключён.")
            }
            let args = (x["args"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]) ?? [:]
            return Agent.MCP.text(try await mcp(server, method: "tools/call", params: ["name": tool, "arguments": args]))

        default:
            throw Problem(errorDescription: "Неизвестное действие.")
        }
    }

    private func open(_ url: URL?, _ done: String) async throws -> String {
        guard let url = url else { throw Problem(errorDescription: "Не хватает данных для ссылки.") }
        guard await UIApplication.shared.open(url) else { throw Problem(errorDescription: "Приложение не открылось — возможно, оно не установлено.") }
        return done
    }

    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "ru_RU")
        d.dateFormat = f
        return d
    }
    private static let day = formatter("d MMM, EEE")
    private static let time = formatter("HH:mm")

    // MARK: MCP servers

    func addServer(name: String, url: String, token: String) async throws {
        let name = name.trimmingCharacters(in: .whitespaces), url = url.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, URL(string: url) != nil else { throw Problem(errorDescription: "Укажите название и адрес.") }
        guard !servers.contains(where: { $0.name == name }) else { throw Problem(errorDescription: "Сервер с таким названием уже есть.") }
        let server = Server(name: name, url: url)
        Keychain.save(token, as: "mcp-" + name)
        do {
            try await refresh(server)
        } catch {
            Keychain.save("", as: "mcp-" + name)
            throw error
        }
        servers.append(server)
        store(servers, "servers")
        _ = await set("mcp:" + name, .read)
    }

    func refresh(_ server: Server) async throws {
        mcpTools[server.name] = Agent.MCP.tools(try await mcp(server, method: "tools/list"))
        store(mcpTools, "mcpTools")
    }

    func remove(_ server: Server) {
        servers.removeAll { $0 == server }
        mcpTools[server.name] = nil
        access["mcp:" + server.name] = nil
        Keychain.save("", as: "mcp-" + server.name)
        store(servers, "servers"); store(mcpTools, "mcpTools"); store(access, "access")
        log("Отключён сервер \(server.name)", status: "настройка")
    }

    // shortcut: a fresh MCP session for every call (3 requests), keep the session id if servers get slow
    private func mcp(_ server: Server, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let url = URL(string: server.url) else { throw Problem(errorDescription: "Неверный адрес сервера.") }
        let token = Keychain.read("mcp-" + server.name)
        let (initData, initResponse) = try await send(try Agent.MCP.request(url: url, token: token, session: nil, id: 1, method: "initialize", params: Agent.MCP.initialize))
        _ = try Agent.MCP.result(initData)
        let session = (initResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id")
        _ = try? await send(try Agent.MCP.request(url: url, token: token, session: session, id: nil, method: "notifications/initialized"))
        let (data, _) = try await send(try Agent.MCP.request(url: url, token: token, session: session, id: 2, method: method, params: params))
        return try Agent.MCP.result(data)
    }

    private func send(_ r: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await URLSession.shared.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw Problem(errorDescription: "Сервер не пустил: проверьте токен.") }
        guard (200..<300).contains(code) else { throw Problem(errorDescription: "Сервер ответил \(code).") }
        return (data, response)
    }

    // MARK: storage

    private func load<T: Decodable>(_ key: String, from d: UserDefaults) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func store<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
    private func loadFile<T: Decodable>(_ name: String) -> T? {
        (try? Data(contentsOf: dir.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func saveFile<T: Encodable>(_ value: T, _ name: String) {
        try? JSONEncoder().encode(value).write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }
}
