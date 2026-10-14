import SwiftUI

/// «Коннекторы» (like Muse): which apps Kimy may use and how far, what Kimy remembers, what Kimy has done.
struct ConnectorsView: View {
    enum Tab: String, CaseIterable { case apps = "Приложения", memory = "Память", journal = "Журнал" }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Connectors.shared
    @State var tab: Tab = .apps
    @State private var note: String?
    @State private var adding = false
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var working = false

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Picker("Раздел", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let note = note {
                        Text(note).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5))
                    }
                    switch tab {
                    case .apps: apps
                    case .memory: memory
                    case .journal: journal
                    }
                }
                .padding(16)
            }
        }
        .foregroundColor(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.05), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")
            VStack(alignment: .leading, spacing: 2) {
                Text("Коннекторы").font(Theme.title(24, .heavy))
                Text("Подключено: \(store.connectedCount) · без вашего «Выполнить» Kimy ничего не меняет")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            Spacer()
        }
    }

    // MARK: apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Agent.connectors) { c in
                row(id: c.id, icon: c.icon, title: c.title, about: c.about, read: c.canRead, act: c.canAct)
            }
            Text("Сервисы (MCP)").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundColor(Theme.muted).padding(.top, 6)
            ForEach(store.servers) { s in
                VStack(alignment: .leading, spacing: 8) {
                    row(id: "mcp:" + s.name, icon: "puzzlepiece.extension", title: s.name,
                        about: "\(store.mcpTools[s.name]?.count ?? 0) инструментов · \(URL(string: s.url)?.host ?? s.url)", read: true, act: true, card: false)
                    HStack {
                        Button("Обновить") { Task { await refresh(s) } }.disabled(working)
                        Spacer()
                        Button("Отключить", role: .destructive) { store.remove(s) }
                    }
                    .font(.system(size: 13))
                }
                .padding(12).glass(20)
            }
            if adding { addForm } else {
                Button { adding = true } label: {
                    Label("Подключить сервис", systemImage: "plus").font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48).glass(24)
                }
                .buttonStyle(.plain)
            }
            Text("Любой сервис с MCP-сервером: GitHub, Linear, Notion, свои серверы. Действия из чата Kimy сначала показывает вам.")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private func row(id: String, icon: String, title: String, about: String, read: Bool, act: Bool, card: Bool = true) -> some View {
        let levels: [Agent.Access] = [.off] + (read ? [.read] : []) + (act ? [.act] : [])
        let current = store.access[id] ?? .off
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(current == .off ? Color.white.opacity(0.1) : Theme.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(about).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            Picker(title, selection: Binding(get: { current }, set: { level in Task { note = await store.set(id, level) } })) {
                ForEach(levels, id: \.self) { Text(short($0, only: levels.count == 2)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        return Group {
            if card { content.padding(12).glass(20) } else { content }
        }
    }

    private func short(_ level: Agent.Access, only: Bool) -> String {
        switch level {
        case .off: return "Выкл"
        case .read: return only ? "Вкл" : "Чтение"
        case .act: return only ? "Вкл" : "Чтение и действия"
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Новый сервис").font(.system(size: 14, weight: .bold))
            field("Название, например github", text: $name)
            field("Адрес https://…/mcp", text: $url).keyboardType(.URL)
            SecureField("", text: $token, prompt: Text("Токен доступа (если нужен)").foregroundColor(Theme.muted))
                .textInputAutocapitalization(.never).disableAutocorrection(true)
                .padding(.horizontal, 12).frame(height: 44)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Button("Отмена") { adding = false; token = "" }
                Spacer()
                Button { Task { await add() } } label: {
                    HStack { if working { ProgressView().tint(.white) }; Text("Подключить") }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 18).frame(height: 44).background(Theme.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(working || name.isEmpty || url.isEmpty)
            }
            Text("Токен хранится в Связке ключей iPhone и уходит только на этот адрес.").font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .padding(12).glass(20)
    }

    private func field(_ hint: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(hint).foregroundColor(Theme.muted))
            .textInputAutocapitalization(.never).disableAutocorrection(true)
            .padding(.horizontal, 12).frame(height: 44)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func add() async {
        working = true
        defer { working = false }
        do {
            try await store.addServer(name: name, url: url, token: token)
            adding = false; name = ""; url = ""; token = ""; note = nil
        } catch {
            note = error.localizedDescription
        }
    }

    private func refresh(_ s: Connectors.Server) async {
        working = true
        defer { working = false }
        do { try await store.refresh(s); note = nil } catch { note = error.localizedDescription }
    }

    // MARK: memory

    private var memory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kimy запоминает важное, что вы о себе рассказали, и учитывает это в ответах. Можно сказать «забудь…» или удалить здесь. Хранится только на этом iPhone.")
                .font(.system(size: 13)).foregroundColor(Theme.soft)
            if store.memory.isEmpty {
                Text("Пока ничего не запомнено.").font(.system(size: 14)).foregroundColor(Theme.muted).padding(.top, 8)
            }
            ForEach(Array(store.memory.enumerated()), id: \.offset) { i, fact in
                HStack(alignment: .top) {
                    Text(fact).font(.system(size: 15))
                    Spacer()
                    Button { store.forget(at: IndexSet(integer: i)) } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Забыть: \(fact)")
                }
                .padding(.leading, 12).padding(.vertical, 4).glass(16)
            }
            if !store.memory.isEmpty {
                Button("Забыть всё", role: .destructive) { store.forgetAll() }.font(.system(size: 14)).padding(.top, 6)
            }
        }
    }

    // MARK: journal

    private var journal: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.journal.isEmpty {
                Text("Здесь будет всё, что Kimy сделал или пытался сделать.").font(.system(size: 14)).foregroundColor(Theme.muted)
            }
            ForEach(store.journal) { e in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(e.status).font(.system(size: 12, weight: .semibold)).foregroundColor(color(e.status))
                        Spacer()
                        Text(e.date, style: .relative).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                    Text(e.text).font(.system(size: 14)).lineLimit(4)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).glass(14)
            }
        }
    }

    private func color(_ status: String) -> Color {
        switch status {
        case "выполнено": return Theme.mint
        case "ошибка", "не разрешено": return Color(red: 1, green: 0.54, blue: 0.5)
        case "отменено": return Theme.orange
        default: return Theme.sky
        }
    }
}

/// «Kimy хочет: …» — nothing on the owner's behalf happens without this card.
struct ApprovalCard: View {
    let action: Agent.Action
    let approve: () -> Void
    let decline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill").font(.system(size: 15)).foregroundColor(.white)
                    .frame(width: 34, height: 34).background(Theme.orange, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kimy хочет").font(.system(size: 14, weight: .bold))
                    Text(Agent.describe(action)).font(.system(size: 14)).foregroundColor(Theme.soft).lineLimit(8)
                }
            }
            HStack(spacing: 8) {
                Button(action: approve) {
                    Text("Выполнить").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44).background(Theme.blue, in: Capsule())
                }
                Button(action: decline) {
                    Text("Отмена").font(.system(size: 15)).frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glass(22, border: Theme.orange.opacity(0.6))
    }
}
