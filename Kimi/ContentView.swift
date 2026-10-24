import SwiftUI

/// Home and chat in one screen (approved design: «Главная» and «Чат»): Kimy greets on an empty chat,
/// the conversation replaces the greeting, the glass input bar stays at the bottom.
struct ContentView: View {
    @StateObject private var chat = ChatModel()
    @StateObject private var voice = Voice()
    @State private var draft = ""
    @State private var showSettings = false
    @State private var showWelcome = isNewUser
    @State private var showOffice = false
    @State private var showConnectors = false
    @State private var showIdea = false
    @ObservedObject private var connectors = Connectors.shared
    @ObservedObject private var fitness = Fitness.shared
    @State private var pending = 0
    @State private var attached: [(name: String, text: String)] = []
    @State private var picking = false
    @State private var report: SharedFile?
    @State private var spoken = false   // the last question was by voice: answer after an approval aloud too
    @Environment(\.scenePhase) private var scenePhase

    private var phase: KimiPhase {
        voice.listening ? .listening : chat.busy ? .thinking : voice.speaking ? .speaking : .idle
    }

    var body: some View {
        ZStack {
            NightBackground()
            VStack(spacing: 12) {
                header
                if chat.visible.isEmpty && !chat.busy && chat.pending == nil {
                    home
                } else {
                    messageList
                }
                notes
                inputBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .foregroundColor(Theme.text)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .background(EmptyView().fullScreenCover(isPresented: $showWelcome) {
            WelcomeView { showWelcome = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showSettings = true } }
        })
        .background(EmptyView().sheet(isPresented: $showOffice, onDismiss: { Task { await loadPending() } }) { OfficeView(voice: voice) })
        .background(EmptyView().sheet(isPresented: $showConnectors) { ConnectorsView() })
        .background(EmptyView().fullScreenCover(isPresented: $showIdea) { IdeaView() })
        .background(EmptyView().sheet(item: $report) { ShareSheet(items: [$0.url]) })
        .task { await loadPending(); await refreshSteps() }
        // Kimy stays in the Dynamic Island / on the lock screen after the app is minimised
        .onAppear { Island.shared.refresh(phase) }
        .onChange(of: phase) { Island.shared.show($0) }
        .onChange(of: scenePhase) {
            if $0 == .active { Island.shared.refresh(phase); Task { await loadPending(); await refreshSteps() } }
        }
    }

    // MARK: header — menu, Kimy pill, Office pill with the number of decisions waiting

    private var header: some View {
        HStack {
            circleButton("line.3.horizontal", label: "Настройки") { showSettings = true }
            Spacer()
            HStack(spacing: 8) {
                GhostBadge(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kimy").font(Theme.title(15))
                    Text(voice.listening ? "слушает" : chat.busy ? "думает…" : voice.speaking ? "говорит" : "на связи")
                        .font(.system(size: 11)).foregroundColor(Theme.mint)
                }
            }
            .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08)))
            Spacer()
            Button { showOffice = true } label: {
                HStack(spacing: 8) {
                    Text("Офис").font(Theme.title(14))
                    if pending > 0 { counter(pending) }
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Theme.violet.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.227, green: 0.196, blue: 0.439)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pending > 0 ? "Офис, ждут решения: \(pending)" : "Офис")
        }
        .padding(.top, 4)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.05), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func counter(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 3)
            .background(Theme.orange, in: Capsule())
    }

    // MARK: home — Kimy, greeting, Office card, quick questions

    private var home: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            KimyHero(size: 112, listening: voice.listening)
            VStack(spacing: 6) {
                Text(Settings.name.isEmpty ? "Привет!" : "Привет, \(Settings.name)").font(Theme.title(26, .medium))
                Text("Чем займёмся?").font(Theme.title(26, .heavy)).foregroundColor(Theme.sky)
            }
            .multilineTextAlignment(.center)
            Text("Нажмите 〰 и говорите — Kimy ответит голосом").font(.system(size: 14)).foregroundColor(Theme.muted)
            Spacer(minLength: 0)

            Button { showOffice = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "building.2").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(Theme.violet, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Офис").font(Theme.title(16))
                        Text(Keychain.read(Keychain.office).isEmpty ? (pending > 0 ? "Ваш ИИ-офис · \(pending) ждёт решения" : "Ваш ИИ-офис: команда под ваш бизнес")
                             : (pending > 0 ? "16 сотрудников · \(pending) ждёт решения" : "16 сотрудников")).font(.system(size: 13)).foregroundColor(Theme.soft)
                    }
                    Spacer()
                    if pending > 0 { counter(pending) }
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(LinearGradient(colors: [Theme.violet.opacity(0.28), Theme.violet.opacity(0.08)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(red: 0.227, green: 0.196, blue: 0.439)))
            }
            .buttonStyle(.plain)

            Button { showConnectors = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(Theme.blue, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Коннекторы").font(Theme.title(16))
                        Text(connectors.connectedCount == 0 ? "Календарь, сообщения, команды, сервисы" : "Подключено: \(connectors.connectedCount)")
                            .font(.system(size: 13)).foregroundColor(Theme.soft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glass(20)
            }
            .buttonStyle(.plain)

            trainerCard

            HStack(spacing: 10) {
                quick("calendar", "Что у меня завтра?", tint: Theme.blue, fg: Theme.sky) { Task { await ask("Что у меня завтра?", voice: false) } }
                quick("lightbulb.fill", "Идея · прожарка идеи", tint: IdeaView.ember, fg: IdeaView.ember) { showIdea = true }
            }
        }
    }

    /// Personal trainer: today's steps against the goal; a tap starts (or continues) the plan in the chat.
    private var trainerCard: some View {
        Button { Task { await ask("Будь моим персональным тренером: тренировки, шаги и питание.", voice: false) } } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.green.opacity(0.2), lineWidth: 5)
                    Circle().trim(from: 0, to: fitness.goal > 0 ? min(Double(fitness.today ?? 0) / Double(fitness.goal), 1) : 0)
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "figure.walk").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.mint)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тренер").font(Theme.title(16))
                    Text(fitness.today.map { n in fitness.goal > 0 ? "Шаги: \(n) из \(fitness.goal)" : "Шаги сегодня: \(n)" } ?? "Тренировки, шаги, питание")
                        .font(.system(size: 13)).foregroundColor(Theme.soft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .glass(20, border: Theme.green.opacity(0.35))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fitness.today.map { "Тренер. Шаги сегодня \($0)" + (fitness.goal > 0 ? " из \(fitness.goal)" : "") } ?? "Тренер")
    }

    private func quick(_ icon: String, _ title: String, tint: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(fg)
                    .frame(width: 30, height: 30).background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.system(size: 14)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 44)
            .glass(18)
        }
        .buttonStyle(.plain)
    }

    // MARK: chat

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.visible) { message in
                        Bubble(message: message) { text in
                            if let url = Files.report(text) { report = SharedFile(url: url) } else { chat.error = "Не удалось сохранить PDF." }
                        }
                        .id(message.id)
                    }
                    if chat.busy { TypingDots().id("busy") }
                    if let action = chat.pending, !chat.busy {
                        ApprovalCard(action: action, approve: { Task { await approve() } }, decline: { chat.decline() }).id("pending")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: chat.messages.count) { _ in
                withAnimation {
                    if chat.busy { proxy.scrollTo("busy", anchor: .bottom) }
                    else if chat.pending != nil { proxy.scrollTo("pending", anchor: .bottom) }
                    else if let id = chat.visible.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        if let error = chat.error {
            Text(error).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5))
        }
        if voice.listening {
            Text(voice.heard.isEmpty ? (voice.conversation ? "Слушаю… скажите «стоп», чтобы закончить" : "Слушаю…") : voice.heard).font(.footnote).foregroundColor(Theme.soft)
        } else if let note = voice.note {
            Text(note).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5))
        }
        if !chat.visible.isEmpty && !chat.busy {
            HStack(spacing: 8) {
                chip("Новый чат") { chat.clear() }
                chip("Коннекторы") { showConnectors = true }
                chip("Офис") { showOffice = true }
                chip("Идея") { showIdea = true }
                Spacer()
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13)).foregroundColor(Theme.soft).padding(.horizontal, 14).frame(height: 36).glass(18)
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attached.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(attached.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text").font(.system(size: 12))
                                Text(f.name).font(.system(size: 12)).lineLimit(1)
                                Button { attached.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24) }
                                    .buttonStyle(.plain).accessibilityLabel("Убрать \(f.name)")
                            }
                            .padding(.leading, 10).frame(height: 30).background(Theme.blue.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 6).padding(.top, 4)
                }
            }
            HStack(spacing: 4) {
            Button { picking = true } label: {
                Image(systemName: "paperclip").font(.system(size: 18, weight: .medium)).frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Прикрепить файл")
            .disabled(chat.busy)
            .fileImporter(isPresented: $picking, allowedContentTypes: Files.types, allowsMultipleSelection: true) { result in
                do {
                    for url in try result.get() { attached.append(try Files.read(url)) }
                } catch {
                    chat.error = error.localizedDescription
                }
            }
            TextField("", text: $draft, prompt: Text("Спросите Kimy…").foregroundColor(Theme.muted))
                .font(.system(size: 16))
                .submitLabel(.send)
                .onSubmit { send() }
            if draft.trimmingCharacters(in: .whitespaces).isEmpty && attached.isEmpty {
                Button {
                    voice.converse { text in Task { await heard(text) } }
                } label: {
                    Image(systemName: voice.conversation || voice.listening ? "stop.fill" : "waveform")
                        .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(voice.conversation || voice.listening ? Color.red : Theme.blue, in: Circle())
                        .shadow(color: Theme.blue.opacity(0.55), radius: 12)
                }
                .accessibilityLabel(voice.conversation ? "Закончить разговор" : "Поговорить голосом")
                .disabled(chat.busy)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 44, height: 44).background(Theme.blue, in: Circle())
                }
                .accessibilityLabel("Отправить")
                .disabled(chat.busy)
            }
            }
        }
        .padding(6)
        .glass(26)
    }

    private func send() {
        let text = draft, files = attached
        draft = ""
        attached = []
        if files.isEmpty && KimiCore.opensOffice(text) { showOffice = true; return }
        spoken = false
        Task {
            // a failed question goes back into the field so it can be retried
            if await chat.send(text, voice: false, files: files) == nil {
                if draft.isEmpty { draft = text }
                if attached.isEmpty { attached = files }
            }
        }
    }

    private func ask(_ text: String, voice byVoice: Bool) async {
        if KimiCore.opensOffice(text) { voice.endConversation(); showOffice = true; return }
        spoken = byVoice
        let files = attached
        attached = []
        if let answer = await chat.send(text, voice: byVoice, files: files), byVoice { voice.say(answer, as: SpeechKit.kimy) } else { voice.listenAgain() }
    }

    /// One spoken phrase in the conversation: an answer to «Kimy хочет…» or a new question.
    private func heard(_ text: String) async {
        if chat.pending != nil, let yes = KimiCore.yesNo(text) {
            spoken = true
            if yes { await approve() } else { chat.decline(); voice.say("Хорошо, не делаю.", as: SpeechKit.kimy) }
            return
        }
        await ask(text, voice: true)
    }

    private func approve() async {
        if let answer = await chat.approve(voice: spoken), spoken { voice.say(answer, as: SpeechKit.kimy) } else { voice.listenAgain() }
    }

    private func refreshSteps() async {
        if (connectors.access["health"] ?? .off) != .off { await fitness.refresh() }
    }

    private func loadPending() async {
        guard !Keychain.read(Keychain.office).isEmpty else { return }
        if let root = try? await callOffice({ try Office.request("proposals", token: $0) }) {
            pending = Office.proposals(root).count
        }
    }
}

/// Bold, italics and links from the model's markdown; anything else shown as plain text.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct Bubble: View {
    let message: ChatMessage
    let report: (String) -> Void
    private var mine: Bool { message.role == .user }

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 48) }
            Group {
                if mine {
                    Text(([message.text] + (message.files ?? []).map { "📎 " + $0 }).joined(separator: "\n"))
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .background(Theme.blue, in: BubbleShape(mine: true))
                        .foregroundColor(.white)
                } else {
                    Text(markdown(Agent.clean(message.text)))
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: BubbleShape(mine: false))
                        .background(Color.white.opacity(0.06), in: BubbleShape(mine: false))
                        .overlay(BubbleShape(mine: false).stroke(Color.white.opacity(0.12)))
                        .contextMenu {
                            Button { UIPasteboard.general.string = Agent.clean(message.text) } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                            Button { report(Agent.clean(message.text)) } label: { Label("Отчёт в PDF", systemImage: "doc.richtext") }
                        }
                }
            }
            .font(.system(size: 15))
            .lineSpacing(3)   // no text selection: a long press opens «Скопировать» / «Отчёт в PDF»
            if !mine { Spacer(minLength: 48) }
        }
    }
}

/// Rounded bubble with a smaller corner at the speaker's side, as in the design.
private struct BubbleShape: Shape {
    let mine: Bool
    func path(in r: CGRect) -> Path {
        let big: CGFloat = 20, small: CGFloat = 6
        let bl = mine ? big : small, br = mine ? small : big
        var p = Path()
        p.move(to: CGPoint(x: r.minX + big, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - big, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - big, y: r.minY + big), radius: big, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + big))
        p.addArc(center: CGPoint(x: r.minX + big, y: r.minY + big), radius: big, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// «Kimy печатает»: three hopping dots.
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    let k = max(0, sin((t - Double(i) * 0.15) * 2 * .pi / 1.2))
                    Circle().fill([Theme.text, Theme.muted, Color(red: 0.29, green: 0.31, blue: 0.44)][i])
                        .frame(width: 7, height: 7)
                        .offset(y: still ? 0 : -5 * k)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .glass(18)
        }
        .accessibilityLabel("Kimy печатает")
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.read()
    @State private var officeKey = Keychain.read(Keychain.office)
    @State private var speechKey = Keychain.read(Keychain.speechkit)
    @State private var model = Settings.model
    @State private var name = Settings.name

    var body: some View {
        NavigationView {
            Form {
                Section("Как к вам обращаться") {
                    TextField("Имя", text: $name)
                }
                if !Keychain.read(Keychain.account).isEmpty {
                    Section {
                        NavigationLink(destination: OfficeSetupView()) { Text("Мой офис: настройка") }
                    } header: {
                        Text("Аккаунт Kimy")
                    } footer: {
                        Text("Kimy думает на сервере Kimy. Здесь вы собираете свой ИИ-офис: о бизнесе, группа в Telegram, почта, кодовое слово.")
                    }
                }
                Section {
                    SecureField("Ключ AI Gateway (sk-…)", text: $key)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                } header: {
                    Text("Свой ключ нейросети (необязательно)")
                } footer: {
                    Text("Только если хотите платить за нейросеть сами: тогда Kimy ходит в AI Gateway Timeweb напрямую. Хранится в Связке ключей.")
                }
                Section {
                    SecureField("Ключ входа в Офис", text: $officeKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                } header: {
                    Text("Офис")
                } footer: {
                    Text("Только для владельца сервера Kimy: ключ его собственного офиса (kimi-office.token). Пользователям не нужен.")
                }
                Section {
                    SecureField("API-ключ Yandex SpeechKit", text: $speechKey)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                } header: {
                    Text("Голоса")
                } footer: {
                    Text("Kimy говорит голосом Даши, у каждого сотрудника свой голос. Ключ: Yandex Cloud → сервисный аккаунт с ролью ai.speechkit-tts.user → API-ключ. Без ключа говорит голос iPhone.")
                }
                Section {
                    NavigationLink(destination: ConnectorsView().navigationBarHidden(true)) { Text("Коннекторы, память и журнал") }
                } footer: {
                    Text("Какие приложения Kimy может читать и где действовать — только после вашего «Выполнить».")
                }
                Section("Модель") {
                    TextField(KimiCore.defaultModel, text: $model)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                if #available(iOS 16.0, *) {
                    Section("Siri") {
                        Text("Скажите: «Привет, Siri, спроси Кими» — Siri спросит, что передать.")
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Keychain.save(key)
                        Keychain.save(officeKey, as: Keychain.office)
                        Connectors.shared.officeKeyChanged()
                        Keychain.save(speechKey, as: Keychain.speechkit)
                        Settings.model = model
                        Settings.name = name
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
