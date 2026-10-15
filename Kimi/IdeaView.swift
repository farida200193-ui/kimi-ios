import SwiftUI

/// «Прожарка идеи»: seven AI advisors around the fire (approved mockup «Kimy · Прожарка идеи»).
/// Idea → council → chairman's questions → debate → scores → verdict with a PDF report.
struct IdeaView: View {
    enum Stage: Int, CaseIterable { case idea, council, questions, debate, scores, verdict }

    @Environment(\.dismiss) private var dismiss
    @State private var stage = Stage.idea
    @State private var idea = ""
    @State private var questions: [String] = []
    @State private var answers: [String] = []
    @State private var result: Council.Result?
    @State private var shown = 0            // debate lines on screen
    @State private var talking: Int?        // advisor index
    @State private var seated = false
    @State private var scored = false
    @State private var ruinBar: Double = 0
    @State private var busy = false
    @State private var error: String?
    @State private var report: SharedFile?

    static let ember = Color(red: 1, green: 0.478, blue: 0.102)       // #FF7A1A
    static let flame = Color(red: 1, green: 0.761, blue: 0.294)       // #FFC24B
    static let red = Color(red: 1, green: 0.302, blue: 0.239)
    static let colors: [Color] = [
        Color(red: 0.298, green: 0.490, blue: 1), Color(red: 0.184, green: 0.749, blue: 0.443), Color(red: 1, green: 0.478, blue: 0.102),
        Color(red: 0.545, green: 0.486, blue: 0.965), Color(red: 0.898, green: 0.702, blue: 0.173), Color(red: 1, green: 0.361, blue: 0.541),
        Color(red: 0.180, green: 0.769, blue: 0.839),
    ]
    private let names = ["ИДЕЯ", "СОВЕТ", "ВОПРОСЫ", "СПОР", "ОЦЕНКИ", "ВЕРДИКТ"]

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            RadialGradient(colors: [Self.ember.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 320).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        header
                        stages
                        scene.frame(height: 340)
                        Text(caption).font(Theme.title(16, .heavy)).multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color(red: 0.08, green: 0.055, blue: 0.08).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        panel.padding(14).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08)))
                            .padding(.horizontal, 14)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: shown) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .foregroundColor(Theme.text)
        .preferredColorScheme(.dark)
        .onAppear { UITextView.appearance().backgroundColor = .clear }
        .sheet(item: $report) { ShareSheet(items: [$0.url]) }
    }

    // MARK: top

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.05), in: Circle()).overlay(Circle().stroke(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain).accessibilityLabel("Назад")
            VStack(alignment: .leading, spacing: 2) {
                Text("Идея").font(Theme.title(22, .heavy))
                Text("Прожарка идеи · 7 ИИ-советников").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var stages: some View {
        HStack(spacing: 5) {
            ForEach(Stage.allCases, id: \.self) { s in
                if s != .idea { Text("·").foregroundColor(Color(white: 0.4)) }
                Text(names[s.rawValue]).foregroundColor(s == stage ? Self.ember : s.rawValue < stage.rawValue ? Color(white: 0.7) : Color(white: 0.4))
                    .shadow(color: s == stage ? Self.ember.opacity(0.6) : .clear, radius: 6)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6)
        .accessibilityElement(children: .ignore).accessibilityLabel("Этап: \(names[stage.rawValue].lowercased())")
    }

    private var caption: String {
        switch stage {
        case .idea: return "Идея на прожарку"
        case .council: return "7 ИИ-советников за столом"
        case .questions: return busy ? "председатель думает…" : "председатель уточняет"
        case .debate: return busy ? "советники готовятся…" : "советники спорят"
        case .scores: return "каждый ставит оценку"
        case .verdict: return "на выходе — вердикт"
        }
    }

    // MARK: the table

    private var scene: some View {
        GeometryReader { g in
            let w = g.size.width, cx = w / 2, cy: CGFloat = 184
            let rx = min(158, w / 2 - 38), ry: CGFloat = 104
            ZStack {
                ring(340, 200, 0.25).position(x: cx, y: cy + 6)
                ring(300, 170, 1).position(x: cx, y: cy + 6)
                ring(220, 116, 0.5).position(x: cx, y: cy + 6)
                Fire().frame(width: 90, height: 90).position(x: cx, y: cy - 6)
                Text("ТВОЯ ИДЕЯ").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(red: 0.1, green: 0.07, blue: 0.094), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Self.ember))
                    .shadow(color: Self.ember.opacity(0.5), radius: 8)
                    .position(x: cx, y: cy + 20)
                ForEach(Array(Council.advisors.enumerated()), id: \.offset) { i, a in
                    let angle = -Double.pi / 2 + Double(i) * 2 * .pi / 7
                    let depth = (sin(angle) + 1) / 2
                    seat(i, a, size: 38 + depth * 16)
                        .position(x: cx + rx * cos(angle), y: cy + ry * sin(angle) + 4)
                        .zIndex(depth)
                        .opacity(seated ? 1 : 0)
                        .scaleEffect(seated ? 1 : 0.6)
                        .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(Double(i) * 0.12), value: seated)
                }
            }
        }
    }

    private func ring(_ w: CGFloat, _ h: CGFloat, _ opacity: Double) -> some View {
        Ellipse().stroke(Self.ember, lineWidth: opacity == 1 ? 2 : 1).frame(width: w, height: h)
            .shadow(color: Self.ember.opacity(0.6), radius: 10).opacity(opacity)
    }

    private func score(of i: Int) -> Int? {
        let name = Council.advisors[i].name.lowercased()
        return result?.scores.first { $0.who.lowercased().contains(name) }?.score
    }

    private func seat(_ i: Int, _ a: Council.Advisor, size: CGFloat) -> some View {
        let on = talking == i
        return VStack(spacing: 0) {
            if scored, let s = score(of: i) {
                (Text("\(s)").font(Theme.title(20, .heavy)) + Text("/10").font(.system(size: 9)).foregroundColor(Theme.muted))
                    .foregroundColor(s <= 3 ? Self.red : Theme.text)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color(red: 0.063, green: 0.047, blue: 0.07), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(s <= 3 ? Self.red : Self.ember.opacity(0.3)))
                    .transition(.scale)
                    .padding(.bottom, 2)
            }
            GhostBadge(color: Self.colors[i], size: size)
                .shadow(color: Self.ember.opacity(on ? 1 : 0.35), radius: on ? 14 : 7)
            Text(a.name.uppercased()).font(.system(size: 8.5, weight: .heavy, design: .rounded))
                .foregroundColor(on ? Color(red: 0.086, green: 0.043, blue: 0.02) : Theme.text)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(on ? Self.ember : Color(red: 0.063, green: 0.047, blue: 0.07), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Self.ember.opacity(on ? 1 : 0.3)))
                .offset(y: -4)
            Text(a.focus).font(.system(size: 9)).foregroundColor(Theme.muted).offset(y: -3)
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.25), value: on)
        .accessibilityElement(children: .combine)
    }

    // MARK: the panel

    @ViewBuilder private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch stage {
            case .idea:
                Text("Ваша идея").font(.system(size: 14, weight: .bold))
                ZStack(alignment: .topLeading) {
                    if idea.isEmpty { Text("Например: открыть кофейню у дома").foregroundColor(Theme.muted).padding(.top, 8).padding(.leading, 5) }
                    TextEditor(text: $idea).frame(minHeight: 80).accessibilityLabel("Идея")
                }
                .padding(4).background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                go("Собрать совет", disabled: idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await askQuestions() } }
            case .council, .questions:
                HStack(spacing: 10) {
                    GhostBadge(size: 28)
                    Text(busy || questions.isEmpty ? "Председатель Kimy думает над вопросами…" : "Прежде чем совет начнёт — три вопроса:")
                        .font(.system(size: 14, weight: .bold))
                    if busy { ProgressView().tint(Self.ember) }
                }
                ForEach(questions.indices, id: \.self) { k in
                    Text(questions[k]).font(.system(size: 14, weight: .semibold))
                    TextField("", text: $answers[k], prompt: Text("Ответ (можно пропустить)").foregroundColor(Theme.muted))
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14)))
                }
                if !questions.isEmpty { go("Начать спор", disabled: busy) { Task { await runCouncil() } } }
            case .debate:
                if busy {
                    HStack { ProgressView().tint(Self.ember); Text("Советники спорят — это займёт до минуты…").font(.system(size: 14)) }
                }
                ForEach(Array((result?.debate ?? []).prefix(shown).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(color(of: line.who)).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.who.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundColor(Self.flame)
                            Text(line.say).font(.system(size: 14))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let r = result { go("К оценкам", disabled: shown < r.debate.count) { toScores() } }
            case .scores:
                if let r = result {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Council.format(r.ruin)).font(Theme.title(30, .heavy))
                            Text("из 10").font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule().fill(LinearGradient(colors: [Self.flame, Self.ember, Self.red], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: g.size.width * ruinBar / 10)
                                }
                            }
                            .frame(height: 10)
                            Text("риск разорения").font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    scoreList(r, why: true)
                    go("Вердикт") { withAnimation { stage = .verdict } }
                }
            case .verdict:
                if let r = result {
                    VStack(spacing: 6) {
                        Text("ВЕРДИКТ \(Council.format(r.average))/10").font(Theme.title(18, .heavy))
                        Text(Council.verdict(r.average)).font(Theme.title(16, .heavy)).foregroundColor(Self.ember).multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16).padding(.horizontal, 20).frame(maxWidth: .infinity)
                    .background(Color(red: 0.082, green: 0.05, blue: 0.063), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Self.ember, lineWidth: 2))
                    .shadow(color: Self.ember.opacity(0.55), radius: 18)
                    .transition(.scale)
                    scoreList(r, why: false)
                    if !r.conditions.isEmpty {
                        Text("Условия").font(.system(size: 14, weight: .bold))
                        ForEach(r.conditions, id: \.self) { Text("• \($0)").font(.system(size: 13)) }
                    }
                    HStack(spacing: 8) {
                        go("Отчёт в PDF") {
                            let answered = zip(questions, answers).map { (q: $0.0, a: $0.1) }
                            if let url = Files.report(Council.report(idea: idea, answers: answered, result: r)) { report = SharedFile(url: url) }
                        }
                        Button("Новая идея") { restart() }
                            .font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().stroke(Color.white.opacity(0.18))).buttonStyle(.plain)
                    }
                }
            }
            if let error = error {
                Text(error).font(.footnote).foregroundColor(Color(red: 1, green: 0.54, blue: 0.5))
            }
        }
    }

    private func scoreList(_ r: Council.Result, why: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.scores.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.who.uppercased()).font(.system(size: 11, weight: .heavy, design: .rounded)).frame(width: 112, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(s.score)").font(Theme.title(13, .heavy)).foregroundColor(s.score <= 3 ? Self.red : Theme.text).frame(width: 24, alignment: .leading)
                    if why { Text(s.why).font(.system(size: 13)).foregroundColor(Theme.muted) }
                }
            }
        }
    }

    private func go(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .heavy)).foregroundColor(Color(red: 0.1, green: 0.05, blue: 0.016))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Self.ember, in: Capsule())
                .shadow(color: Self.ember.opacity(disabled ? 0 : 0.5), radius: 12)
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1)
    }

    private func color(of who: String) -> Color {
        let i = Council.advisors.firstIndex { who.lowercased().contains($0.name.lowercased()) }
        return i.map { Self.colors[$0] } ?? Self.ember
    }

    // MARK: flow

    private func ask(_ prompt: String) async throws -> String {
        try await askKimi(history: [ChatMessage(role: .user, text: prompt)], voice: false)
    }

    private func askQuestions() async {
        error = nil
        withAnimation { stage = .council }
        seated = true
        busy = true
        defer { busy = false }
        do {
            let qs = Council.questions(try await ask(Council.questionsPrompt(idea)))
            questions = qs.isEmpty ? ["Какой бюджет?", "Какие сроки?", "Что уже пробовали?"] : qs
            answers = Array(repeating: "", count: questions.count)
            withAnimation { stage = .questions }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runCouncil() async {
        error = nil
        withAnimation { stage = .debate }
        busy = true
        let answered = zip(questions, answers).map { (q: $0.0, a: $0.1) }
        do {
            guard let r = Council.result(try await ask(Council.councilPrompt(idea, answers: answered))) else {
                busy = false
                error = "Совет ответил непонятно. Нажмите «Начать спор» ещё раз."
                stage = .questions
                return
            }
            result = r
            busy = false
            for (k, line) in r.debate.enumerated() {
                talking = Council.advisors.firstIndex { line.who.lowercased().contains($0.name.lowercased()) }
                withAnimation(.easeOut(duration: 0.3)) { shown = k + 1 }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if stage != .debate { return }
            }
            talking = nil
        } catch {
            busy = false
            self.error = error.localizedDescription
            stage = .questions
        }
    }

    private func toScores() {
        talking = nil
        withAnimation { stage = .scores }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { scored = true }
        withAnimation(.easeOut(duration: 1.2)) { ruinBar = result?.ruin ?? 0 }
    }

    private func restart() {
        withAnimation {
            stage = .idea; idea = ""; questions = []; answers = []; result = nil
            shown = 0; talking = nil; seated = false; scored = false; ruinBar = 0; error = nil
        }
    }
}

/// The fire in the middle of the table: three flickering tongues.
private struct Fire: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                Circle().fill(RadialGradient(colors: [IdeaView.ember.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 110, height: 110).offset(y: 20)
                ForEach(0..<3) { i in
                    let k = sin(t * (5.5 + Double(i) * 1.7) + Double(i))
                    Ellipse()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.77), IdeaView.flame, IdeaView.ember, IdeaView.ember.opacity(0)],
                                             center: UnitPoint(x: 0.5, y: 0.8), startRadius: 0, endRadius: 40))
                        .frame(width: 34, height: i == 0 ? 66 : i == 1 ? 48 : 52)
                        .scaleEffect(x: 1 - 0.06 * k, y: 1 + 0.1 * k, anchor: .bottom)
                        .offset(x: CGFloat(i == 0 ? 0 : i == 1 ? -18 : 18))
                        .blur(radius: 1.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
