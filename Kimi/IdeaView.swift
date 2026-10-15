import SwiftUI

/// «Идея» — прожарка идеи (approved mockup «Kimy · Прожарка идеи»): seven AI advisors around the fire,
/// the chairman (Kimy) asks, they argue, score, and give a verdict with a PDF report.
struct IdeaView: View {
    enum Stage: Int, CaseIterable {
        case idea, council, questions, debate, scores, verdict
        var title: String { ["ИДЕЯ", "СОВЕТ", "ВОПРОСЫ", "СПОР", "ОЦЕНКИ", "ВЕРДИКТ"][rawValue] }
    }

    static let ember = Color(red: 1, green: 0.478, blue: 0.102)     // #FF7A1A
    static let flame = Color(red: 1, green: 0.761, blue: 0.294)     // #FFC24B
    static let red = Color(red: 1, green: 0.302, blue: 0.239)       // #FF4D3D
    static let seatColors: [Color] = [
        Color(red: 0.30, green: 0.49, blue: 1), Color(red: 0.18, green: 0.75, blue: 0.44), Color(red: 1, green: 0.48, blue: 0.10),
        Color(red: 0.55, green: 0.49, blue: 0.96), Color(red: 0.90, green: 0.70, blue: 0.17), Color(red: 1, green: 0.36, blue: 0.54),
        Color(red: 0.18, green: 0.77, blue: 0.84),
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var stage = Stage.idea
    @State private var idea = ""
    @State private var questions: [String] = []
    @State private var answers: [String] = []
    @State private var result: Council.Result?
    @State private var shown = 0          // debate lines on screen
    @State private var seated = false
    @State private var busy = false
    @State private var error: String?
    @State private var report: SharedFile?
    @FocusState private var field: Int?   // -1 the idea, 0… the answers; while typing the table shrinks so the button stays above the keyboard

    private var ember: Color { Self.ember }

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            RadialGradient(colors: [ember.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 380).ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        header
                        stageBar
                        table
                            .scaleEffect(field == nil ? 1 : 0.5, anchor: .top)
                            .frame(height: field == nil ? 340 : 170, alignment: .top)
                            .contentShape(Rectangle())
                            .onTapGesture { field = nil }   // tap the table to hide the keyboard
                        caption
                        panel.id("panel")
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.bottom, 20)
                }
                .onChange(of: shown) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: field) { f in
                    guard f != nil else { return }
                    // after the keyboard has slid in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                }
                .onChange(of: idea) { _ in if field != nil { proxy.scrollTo("end", anchor: .bottom) } }
                .animation(.easeOut(duration: 0.25), value: field)
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
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")
            VStack(alignment: .leading, spacing: 2) {
                Text("Идея").font(Theme.title(20, .heavy))
                Text("Прожарка идеи · 7 ИИ-советников").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    private var stageBar: some View {
        HStack(spacing: 5) {
            ForEach(Stage.allCases, id: \.self) { s in
                if s != .idea { Text("·").foregroundColor(Color(white: 0.4)) }
                Text(s.title).tracking(0.8)   // View.tracking is iOS 16, Text.tracking works on 15
                    .foregroundColor(s == stage ? ember : s.rawValue < stage.rawValue ? Color(red: 0.73, green: 0.66, blue: 0.63) : Color(white: 0.42))
                    .shadow(color: s == stage ? ember.opacity(0.7) : .clear, radius: 6)
            }
        }
        .font(.system(size: 9.5, weight: .bold, design: .rounded))
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Этап: \(stage.title.lowercased())")
    }

    // MARK: the table

    private var talking: Int? {
        guard stage == .debate, shown > 0, let r = result, shown <= r.debate.count else { return nil }
        return seat(of: r.debate[shown - 1].who)
    }

    private func seat(of who: String) -> Int? {
        let w = who.lowercased()
        return Council.advisors.firstIndex { w.hasPrefix($0.name.lowercased()) || $0.name.lowercased().hasPrefix(w) }
    }

    private func score(_ i: Int) -> Council.Score? {
        result?.scores.first { seat(of: $0.who) == i }
    }

    private var table: some View {
        GeometryReader { g in
            let w = g.size.width, cx = w / 2, cy: CGFloat = 190
            let rx = min(158, w / 2 - 38), ry: CGFloat = 104
            ZStack {
                ring(340, 200, 0.25, dashed: true).position(x: cx, y: cy)
                ring(300, 170, 1, dashed: false).position(x: cx, y: cy)
                ring(220, 116, 0.5, dashed: false).position(x: cx, y: cy)
                Fire().frame(width: 90, height: 90).position(x: cx, y: cy - 34)
                Text("ТВОЯ ИДЕЯ").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.6)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(red: 0.10, green: 0.07, blue: 0.09), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(ember))
                    .shadow(color: ember.opacity(0.6), radius: 8)
                    .position(x: cx, y: cy + 8)
                ForEach(0..<Council.advisors.count, id: \.self) { i in
                    let angle = -Double.pi / 2 + Double(i) * 2 * .pi / Double(Council.advisors.count)
                    let depth = (sin(angle) + 1) / 2
                    let size = 38 + CGFloat(depth) * 16
                    seatView(i, size: size)
                        .position(x: cx + rx * CGFloat(cos(angle)), y: cy + ry * CGFloat(sin(angle)) + 34 - (size * 1.1 + 34) / 2)
                        .zIndex(depth * 10)
                        .opacity(seated ? 1 : 0)
                        .scaleEffect(seated ? 1 : 0.6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.12), value: seated)
                }
            }
        }
    }

    private func ring(_ w: CGFloat, _ h: CGFloat, _ opacity: Double, dashed: Bool) -> some View {
        Ellipse()
            .stroke(ember, style: StrokeStyle(lineWidth: dashed ? 1 : 2, dash: dashed ? [5, 4] : []))
            .frame(width: w, height: h)
            .shadow(color: ember.opacity(0.7), radius: 10)
            .opacity(opacity)
    }

    private func seatView(_ i: Int, size: CGFloat) -> some View {
        let a = Council.advisors[i], on = talking == i, s = score(i)
        let showScore = stage.rawValue >= Stage.scores.rawValue && s != nil
        return VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(s?.score ?? 0)").font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("/10").font(.system(size: 9)).foregroundColor(Theme.muted)
            }
            .foregroundColor((s?.score ?? 10) <= 3 ? Self.red : Theme.text)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color(red: 0.06, green: 0.05, blue: 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke((s?.score ?? 10) <= 3 ? Self.red : ember.opacity(0.35)))
            .scaleEffect(showScore ? 1 : 0.01)
            .opacity(showScore ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.55).delay(Double(i) * 0.18), value: showScore)
            .padding(.bottom, 2)
            GhostBadge(color: Self.seatColors[i], size: size)
                .shadow(color: ember.opacity(on ? 0.95 : 0.4), radius: on ? 14 : 7)
            Text(a.name.uppercased()).font(.system(size: 8.5, weight: .heavy, design: .rounded)).tracking(0.3)
                .foregroundColor(on ? Color(red: 0.09, green: 0.04, blue: 0.02) : Theme.text)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(on ? ember : Color(red: 0.06, green: 0.05, blue: 0.07), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(ember.opacity(0.35)))
                .padding(.top, -4)
                .animation(.easeOut(duration: 0.25), value: on)
            Text(a.focus).font(.system(size: 9)).foregroundColor(Theme.muted)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.name), \(a.focus)" + (showScore ? ", оценка \(s!.score) из 10" : ""))
    }

    // MARK: caption and panel

    private var caption: some View {
        let parts: (String, String, String) = {
            switch stage {
            case .idea: return ("Идея на ", "прожарку", "")
            case .council: return ("", "7", " ИИ-советников за столом")
            case .questions: return ("председатель ", "уточняет", "")
            case .debate: return ("советники ", "спорят", "")
            case .scores: return ("каждый ставит ", "оценку", "")
            case .verdict: return ("на выходе — ", "вердикт", "")
            }
        }()
        return (Text(parts.0) + Text(parts.1).foregroundColor(ember) + Text(parts.2))
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color(red: 0.08, green: 0.05, blue: 0.08).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch stage {
            case .idea: ideaPanel
            case .council: chairman("Председатель Kimy думает над вопросами…", working: true)
            case .questions: questionsPanel
            case .debate: debatePanel
            case .scores: scoresPanel
            case .verdict: verdictPanel
            }
            if let error = error {
                Text(error).font(.footnote).foregroundColor(Self.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08)))
        .padding(.horizontal, 14)
    }

    private var ideaPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ваша идея").font(.system(size: 14, weight: .bold))
            ZStack(alignment: .topLeading) {
                if idea.isEmpty {
                    Text("Например: открыть кофейню у дома").foregroundColor(Theme.muted).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $idea).frame(minHeight: 80).focused($field, equals: -1).accessibilityLabel("Ваша идея")
            }
            .font(.system(size: 15))
            .padding(6)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14)))
            goButton("Собрать совет", enabled: !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { field = nil; Task { await gather() } }
        }
    }

    private func chairman(_ text: String, working: Bool = false) -> some View {
        HStack(spacing: 10) {
            GhostBadge(color: Theme.blue, size: 28)
            Text(text).font(.system(size: 14, weight: .bold))
            if working { ProgressView().tint(ember) }
        }
    }

    private var questionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            chairman("Прежде чем совет начнёт — несколько вопросов:")
            ForEach(questions.indices, id: \.self) { k in
                Text(questions[k]).font(.system(size: 14, weight: .bold))
                TextField("", text: $answers[k], prompt: Text("Ваш ответ").foregroundColor(Theme.muted))
                    .font(.system(size: 15))
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14)))
                    .accessibilityLabel(questions[k])
                    .focused($field, equals: k)
                    .submitLabel(k + 1 < questions.count ? .next : .done)
                    .onSubmit { field = k + 1 < questions.count ? k + 1 : nil }
            }
            goButton("Начать спор", enabled: true) { field = nil; Task { await argue() } }
        }
    }

    private var debatePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = result {
                ForEach(0..<min(shown, r.debate.count), id: \.self) { k in
                    let line = r.debate[k], i = seat(of: line.who)
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(i.map { Self.seatColors[$0] } ?? Theme.muted).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.who.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundColor(Self.flame)
                            Text(line.say).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                goButton("К оценкам", enabled: shown >= r.debate.count) { withAnimation { stage = .scores } }
            } else {
                chairman("Совет спорит… это займёт до минуты", working: true)
            }
        }
    }

    private func scoreList(withWhy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result?.scores ?? [], id: \.who) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.who.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 112, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(s.score)").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundColor(s.score <= 3 ? Self.red : Theme.text).frame(width: 22, alignment: .leading)
                    if withWhy { Text(s.why).font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var scoresPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = result {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Council.format(r.ruin)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("из 10").font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(LinearGradient(colors: [Self.flame, ember, Self.red], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * r.ruin / 10)
                            }
                        }
                        .frame(height: 10)
                        Text("риск разорения").font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Риск разорения \(Council.format(r.ruin)) из 10")
                scoreList(withWhy: true)
                goButton("Вердикт", enabled: true) { withAnimation(.spring()) { stage = .verdict } }
            }
        }
    }

    private var verdictPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = result {
                VStack(spacing: 6) {
                    Text("ВЕРДИКТ \(Council.format(r.average))/10").font(.system(size: 18, weight: .heavy, design: .rounded))
                    Text(Council.verdict(r.average)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(ember)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color(red: 0.08, green: 0.05, blue: 0.06), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ember, lineWidth: 2))
                .shadow(color: ember.opacity(0.6), radius: 18)
                .frame(maxWidth: .infinity)
                .transition(.scale.combined(with: .opacity))
                scoreList(withWhy: false)
                if !r.conditions.isEmpty {
                    Text("Условия").font(.system(size: 14, weight: .bold))
                    ForEach(r.conditions, id: \.self) { Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                }
                HStack(spacing: 8) {
                    goButton("Отчёт в PDF", enabled: true) {
                        let text = Council.report(idea: idea, answers: Array(zip(questions, answers)).map { (q: $0.0, a: $0.1) }, result: r)
                        if let url = Files.report(text) { report = SharedFile(url: url) } else { error = "Не удалось сохранить PDF." }
                    }
                    Button { restart() } label: {
                        Text("Новая идея").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func goButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .heavy)).foregroundColor(Color(red: 0.10, green: 0.05, blue: 0.02))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(ember, in: Capsule())
                .shadow(color: ember.opacity(enabled ? 0.6 : 0), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled && !busy ? 1 : 0.45)
    }

    // MARK: the flow

    private func ask(_ prompt: String) async throws -> String {
        try await askKimi(history: [ChatMessage(role: .user, text: prompt)], voice: false)
    }

    private func gather() async {
        error = nil
        busy = true
        defer { busy = false }
        withAnimation { stage = .council; seated = true }
        do {
            let found = Council.questions(try await ask(Council.questionsPrompt(idea)))
            questions = found.isEmpty ? ["Какой бюджет?", "Когда хотите запустить?", "Что уже пробовали?"] : found
            answers = Array(repeating: "", count: questions.count)
            withAnimation { stage = .questions }
        } catch {
            self.error = error.localizedDescription
            withAnimation { stage = .idea; seated = false }
        }
    }

    private func argue() async {
        error = nil
        busy = true
        result = nil
        shown = 0
        withAnimation { stage = .debate }
        do {
            let qa = Array(zip(questions, answers)).map { (q: $0.0, a: $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            guard let r = Council.result(try await ask(Council.councilPrompt(idea, answers: qa))) else {
                throw Files.Problem(errorDescription: "Совет ответил непонятно. Попробуйте ещё раз.")
            }
            result = r
            busy = false
            for k in 0..<r.debate.count {
                withAnimation(.easeOut(duration: 0.35)) { shown = k + 1 }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
            }
        } catch {
            busy = false
            self.error = error.localizedDescription
            withAnimation { stage = .questions }
        }
    }

    private func restart() {
        withAnimation {
            stage = .idea
            seated = false
            result = nil
            questions = []
            answers = []
            shown = 0
            idea = ""
        }
    }
}

/// The fire in the middle of the table: three flickering flames.
private struct Fire: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                Circle().fill(RadialGradient(colors: [IdeaView.ember.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 110, height: 110).offset(y: 20)
                flame(t, speed: 7.0, phase: 0, width: 34, height: 66, x: 0)
                flame(t, speed: 8.5, phase: 1.3, width: 26, height: 48, x: -16)
                flame(t, speed: 6.1, phase: 2.1, width: 26, height: 52, x: 16)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func flame(_ t: Double, speed: Double, phase: Double, width: CGFloat, height: CGFloat, x: CGFloat) -> some View {
        let k = sin(t * speed + phase)
        return Ellipse()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.77), IdeaView.flame, IdeaView.ember, IdeaView.ember.opacity(0)],
                                 startPoint: .bottom, endPoint: .top))
            .frame(width: width, height: height)
            .scaleEffect(x: 1 - 0.07 * CGFloat(k), y: 1 + 0.1 * CGFloat(k), anchor: .bottom)
            .rotationEffect(.degrees(3 * k), anchor: .bottom)
            .blur(radius: 1.5)
            .offset(x: x)
    }
}
