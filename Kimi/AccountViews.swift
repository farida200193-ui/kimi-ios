import SwiftUI

/// First launch for everyone: an account on the Kimy server in one step. The brain runs there, nothing to configure.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    var ownKey: () -> Void
    @State private var name = ""
    @State private var company = ""
    @State private var invite = ""
    @State private var needInvite = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(spacing: 18) {
                    KimyHero(size: 104)
                    VStack(spacing: 6) {
                        Text("Привет! Я Kimy").font(Theme.title(28, .heavy))
                        Text("Ваш личный ИИ-ассистент. Как к вам обращаться?").font(.system(size: 15)).foregroundColor(Theme.soft)
                    }
                    .multilineTextAlignment(.center)
                    field("Ваше имя", text: $name)
                    field("Компания или проект (необязательно)", text: $company)
                    if needInvite { field("Код приглашения", text: $invite) }
                    if let error = error {
                        Text(error).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5)).multilineTextAlignment(.center)
                    }
                    Button { Task { await start() } } label: {
                        HStack { if busy { ProgressView().tint(.white) }; Text("Начать").font(.system(size: 17, weight: .bold)) }
                            .foregroundColor(.white).frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.blue, in: Capsule()).shadow(color: Theme.blue.opacity(0.5), radius: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Kimy думает на нашем сервере — ключи и настройки не нужны. Свой ИИ-офис можно настроить позже.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
                    Button("У меня свой ключ AI Gateway") { ownKey() }
                        .font(.system(size: 13)).foregroundColor(Theme.sky)
                }
                .padding(24)
            }
        }
        .foregroundColor(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func field(_ hint: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(hint).foregroundColor(Theme.muted))
            .font(.system(size: 16)).padding(.horizontal, 16).frame(height: 50)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12)))
    }

    private func start() async {
        busy = true
        defer { busy = false }
        do {
            let req = try Account.signup(name: name, company: company, invite: invite)
            let (data, response) = try await URLSession.shared.data(for: req)
            let root = try Office.check(data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            guard let token = root["token"] as? String else { throw Office.Failure.server(0, "Сервер не выдал ключ, попробуйте ещё раз.") }
            Keychain.save(token, as: Keychain.account)
            Settings.name = name
            Connectors.shared.officeKeyChanged()
            dismiss()
        } catch {
            let text = error.localizedDescription
            if text.contains("приглашения") { needInvite = true }   // the server still asks for invite codes
            self.error = text
        }
    }
}

/// «Мой офис»: the user's own AI office, set up in four steps (business, Telegram group, mail, code word).
struct OfficeSetupView: View {
    @State private var status = Account.Status()
    @State private var company = ""
    @State private var about = ""
    @State private var offer = ""
    @State private var botToken = ""
    @State private var provider = "gmail"
    @State private var mail = ""
    @State private var mailPassword = ""
    @State private var codeword = ""
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                row("Офис", status.office.isEmpty ? "…" : status.office, ok: status.running)
                if status.chatLimit > 0 { row("Сообщений Kimy сегодня", "\(status.chatToday) из \(status.chatLimit)", ok: true) }
                if let note = note { Text(note).font(.footnote).foregroundColor(Theme.sky) }
            }

            Section {
                TextField("Название компании или проекта", text: $company)
                editor("Чем вы занимаетесь (2–3 предложения)", text: $about)
                editor("Что продаёте и по каким ценам (необязательно)", text: $offer)
                button(status.business ? "Обновить" : "Сохранить", disabled: about.trimmingCharacters(in: .whitespaces).isEmpty) {
                    try await step("setup/business", ["company": company, "about": about, "offer": offer])
                }
            } header: { header("1. О бизнесе", done: status.business) }
              footer: { Text("Из этого офис соберёт команду: директора, ассистента, маркетолога, бухгалтера, юриста и других.") }

            Section {
                if !status.telegramBot {
                    Text("В Telegram откройте @BotFather → /newbot, придумайте имя и вставьте сюда токен бота.").font(.footnote)
                    SecureField("Токен бота 123456:AA…", text: $botToken).textInputAutocapitalization(.never).disableAutocorrection(true)
                    button("Подключить бота", disabled: botToken.isEmpty) { try await step("setup/telegram", ["bot_token": botToken]); botToken = "" }
                } else if !status.telegramGroup {
                    Text("Создайте группу в Telegram, добавьте в неё бота @\(status.bot) и отправьте в группу код:").font(.footnote)
                    Text(status.code).font(.system(size: 20, weight: .bold, design: .monospaced)).textSelection(.enabled)
                    button("Я отправил код — проверить") { try await step("setup/telegram/detect", [:]) }
                } else {
                    Text("Группа «\(status.group)» подключена, бот @\(status.bot).").font(.footnote)
                }
            } header: { header("2. Группа офиса в Telegram", done: status.telegramGroup) }
              footer: { Text("В группе сотрудники обсуждают поручения и присылают вам решения на одобрение.") }

            Section {
                if status.mail.isEmpty {
                    Picker("Почта", selection: $provider) { Text("Gmail").tag("gmail"); Text("Яндекс").tag("yandex"); Text("Mail.ru").tag("mailru") }
                    TextField("Адрес почты", text: $mail).keyboardType(.emailAddress).textInputAutocapitalization(.never).disableAutocorrection(true)
                    SecureField("Пароль приложения", text: $mailPassword)
                    button("Подключить почту", disabled: mail.isEmpty || mailPassword.isEmpty) {
                        try await step("setup/mail", ["provider": provider, "address": mail, "password": mailPassword]); mailPassword = ""
                    }
                } else {
                    Text("Подключена \(status.mail)").font(.footnote)
                }
            } header: { header("3. Почта (необязательно)", done: !status.mail.isEmpty) }
              footer: { Text("Нужен не обычный пароль, а «пароль приложения» из настроек безопасности почты. Сотрудник «отчёты и почта» будет разбирать письма и готовить ответы в вашем стиле — отправка только после вашего одобрения.") }

            Section {
                SecureField("Новое кодовое слово (от 6 букв)", text: $codeword)
                button("Сохранить кодовое слово", disabled: codeword.count < 6 || !status.running) {
                    _ = try await callOffice { try Office.request("codeword", token: $0, body: ["new": codeword]) }
                    codeword = ""
                    note = "Кодовое слово сохранено."
                }
            } header: { header("4. Кодовое слово", done: false) }
              footer: { Text(status.running ? "Им вы одобряете решения сотрудников на экране «Офис». Kimy и сотрудники его не видят." : "Станет доступно, когда офис заработает (шаги 1 и 2).") }
        }
        .navigationTitle("Мой офис")
        .disabled(busy)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(ok ? Theme.mint : Theme.muted) }
    }

    private func header(_ title: String, done: Bool) -> some View {
        HStack { Text(title); if done { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.mint) } }
    }

    private func editor(_ hint: String, text: Binding<String>) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty { Text(hint).foregroundColor(Theme.muted).padding(.top, 8).padding(.leading, 4) }
            TextEditor(text: text).frame(minHeight: 70)
        }
    }

    private func button(_ title: String, disabled: Bool = false, action: @escaping () async throws -> Void) -> some View {
        Button {
            Task {
                busy = true
                defer { busy = false }
                do { try await action(); await refresh() } catch { note = error.localizedDescription }
            }
        } label: { HStack { Text(title); if busy { Spacer(); ProgressView() } } }
        .disabled(disabled)
    }

    private func step(_ path: String, _ body: [String: Any]) async throws {
        _ = try await callAccount(path, body: body)   // the fresh status is read right after
        note = nil
    }

    private func refresh() async {
        do {
            status = Account.status(try await callAccount("me"))
            if company.isEmpty { company = status.company }
        } catch {
            note = error.localizedDescription
        }
    }
}
