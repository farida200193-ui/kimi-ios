import SwiftUI

/// The owner's AI office (approved design «Офис»): decisions waiting for the owner on top, a task for the team,
/// the team as sticker ghosts. Everything here is mirrored by the server into the office Telegram group.
struct OfficeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var voice: Voice
    @State private var task = ""
    @State private var replies: [Office.Reply] = []
    @State private var proposals: [Office.Proposal] = []
    @State private var codeword = ""
    @State private var busy = false
    @State private var error: String?

    struct Member { let name: String; let role: String; let image: String }
    // shortcut: the team is listed in the app, change it here when the office changes (the server has no team endpoint yet)
    private let team: [Member] = [
        Member(name: "Майкл", role: "директор", image: "agent-ceo"), Member(name: "Эрин", role: "бизнес-ассистент", image: "agent-assistant"),
        Member(name: "Джим", role: "маркетолог", image: "agent-marketer"), Member(name: "Пэм", role: "продюсер YouTube", image: "agent-youtube"),
        Member(name: "Филлис", role: "главный редактор", image: "agent-blogger"), Member(name: "Келли", role: "дизайнер", image: "agent-designer"),
        Member(name: "Дуайт", role: "охотник за партнёрами", image: "agent-hunter"), Member(name: "Анджела", role: "бухгалтер", image: "agent-accountant"),
        Member(name: "Оскар", role: "финансист", image: "agent-finance"), Member(name: "Тоби", role: "юрист", image: "agent-lawyer"),
        Member(name: "Райан", role: "ИТ-администратор", image: "agent-it"), Member(name: "Вера", role: "качество продаж", image: "agent-sales"),
        Member(name: "Лев", role: "отчёты и почта", image: "agent-reports"), Member(name: "Макс", role: "фитнес-тренер", image: "agent-fitness"),
        Member(name: "Ева", role: "здоровье", image: "agent-health"), Member(name: "Программист", role: "код и сайты, в песочнице", image: "agent-coder"),
    ]

    var body: some View {
        ZStack {
            NightBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(proposals) { decisionCard($0) }
                    taskCard
                    if !replies.isEmpty { repliesCard }
                    if let error = error {
                        Text(error).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5))
                    }
                    Text("Сотрудники").font(.system(size: 12, weight: .semibold)).tracking(1).foregroundColor(Theme.muted)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(team, id: \.name) { memberCard($0) }
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
        .foregroundColor(Theme.text)
        .preferredColorScheme(.dark)
        .task { await load() }
        .onAppear { UITextView.appearance().backgroundColor = .clear }   // TextEditor sits on glass
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
                Text("Офис").font(Theme.title(24, .heavy))
                Text(proposals.isEmpty ? "\(team.count) сотрудников" : "\(team.count) сотрудников · \(proposals.count) ждёт решения")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            Spacer()
        }
    }

    private func decisionCard(_ p: Office.Proposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill").font(.system(size: 15)).foregroundColor(.white)
                    .frame(width: 34, height: 34).background(Theme.orange, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ждёт вашего решения · №\(p.id)").font(.system(size: 14, weight: .bold))
                    Text(p.text).font(.system(size: 13)).foregroundColor(Theme.soft).lineLimit(8)
                }
            }
            HStack(spacing: 8) {
                SecureField("", text: $codeword, prompt: Text("Кодовое слово").foregroundColor(Theme.muted))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14)))
                Button { Task { await decide(p, approve: true) } } label: {
                    Text("Одобрить").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(height: 44).background(Theme.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy || codeword.isEmpty)
                .opacity(codeword.isEmpty ? 0.5 : 1)
                Button { Task { await decide(p, approve: false) } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Отклонить предложение \(p.id)")
            }
        }
        .padding(14)
        .glass(22, border: Theme.orange.opacity(0.6))
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Поручение").font(.system(size: 14, weight: .bold))
            ZStack(alignment: .topLeading) {
                if task.isEmpty {
                    Text("Например: «Лев, что в почте?»").foregroundColor(Theme.muted).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $task).frame(minHeight: 70).accessibilityLabel("Поручение офису")
            }
            .font(.system(size: 15))
            Button { Task { await ask() } } label: {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? "Офис обсуждает…" : "Дать поручение").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.blue, in: Capsule())
                .shadow(color: Theme.blue.opacity(0.45), radius: 14)
            }
            .buttonStyle(.plain)
            .disabled(busy || task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Без имени отвечает директор. Обсуждение может занять пару минут.").font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .padding(14)
        .glass(22)
    }

    private var repliesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(replies.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let m = member(r.who) { Image(m.image).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true) }
                        Text(r.who).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.sky)
                        Spacer()
                        Button { voice.say(r.text, as: SpeechKit.voice(for: r.who)) } label: {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 14)).frame(width: 44, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Прослушать ответ голосом \(r.who)")
                    }
                    Text(markdown(r.text)).font(.system(size: 15)).textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(22)
    }

    private func memberCard(_ m: Member) -> some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(m.image).resizable().scaledToFit().frame(width: 52, height: 52).accessibilityHidden(true)
                    Spacer()
                    Button { voice.say("Привет! Я \(m.name), \(m.role).", as: SpeechKit.voice(for: m.name)) } label: {
                        Image(systemName: "play.fill").font(.system(size: 12)).frame(width: 32, height: 32)
                            .background(Theme.blue.opacity(0.18), in: Circle()).foregroundColor(Theme.sky)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Голос: \(m.name)")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.system(size: 15, weight: .bold))
                    Text(m.role).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(20)
            .contentShape(Rectangle())
            .onTapGesture { task = "\(m.name), " }   // a card, not a Button: the play button inside must keep its own tap
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(m.name), \(m.role)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Дать поручение") { task = "\(m.name), " }
            .accessibilityAction(named: "Прослушать голос") { voice.say("Привет! Я \(m.name), \(m.role).", as: SpeechKit.voice(for: m.name)) }
    }

    private func member(_ who: String) -> Member? {
        let name = who.components(separatedBy: " · ").first ?? who
        return team.first { $0.name == name }
    }

    private func load() async {
        do {
            proposals = Office.proposals(try await callOffice { try Office.request("proposals", token: $0) })
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func ask() async {
        busy = true
        defer { busy = false }
        do {
            let text = task.trimmingCharacters(in: .whitespacesAndNewlines)
            replies = Office.replies(try await callOffice { try Office.ask(text, token: $0) })
            if replies.isEmpty { replies = [Office.Reply(who: "Офис", text: "Поручение передано, ответ придёт в группу Telegram.")] }
            task = ""
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func decide(_ p: Office.Proposal, approve: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let root = try await callOffice { try Office.decide(p.id, approve: approve, codeword: codeword, token: $0) }
            replies = Office.replies(root)
            if approve { codeword = "" }   // not kept on screen longer than needed
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
