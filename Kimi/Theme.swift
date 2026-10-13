import SwiftUI

/// The approved Kimy design (canvas «Кими — дизайн приложения»): night background with blue, violet and green glows,
/// glass panels, and Kimy — the little sticker ghost with a glowing edge.
enum Theme {
    static let night = Color(red: 0.043, green: 0.047, blue: 0.078)          // #0B0C14
    static let blue = Color(red: 0.118, green: 0.549, blue: 1.0)             // #1E8CFF
    static let violet = Color(red: 0.545, green: 0.486, blue: 0.965)         // #8B7CF6
    static let green = Color(red: 0.122, green: 0.878, blue: 0.486)          // #1FE07C
    static let orange = Color(red: 1.0, green: 0.416, blue: 0.075)           // #FF6A13
    static let ink = Color(red: 0.090, green: 0.086, blue: 0.110)            // #17161C
    static let text = Color(red: 0.945, green: 0.953, blue: 1.0)             // #F1F3FF
    static let muted = Color(red: 0.557, green: 0.576, blue: 0.702)          // #8E93B3
    static let soft = Color(red: 0.776, green: 0.792, blue: 0.890)           // #C6CAE3
    static let sky = Color(red: 0.486, green: 0.725, blue: 1.0)              // #7CB9FF
    static let mint = Color(red: 0.357, green: 0.937, blue: 0.627)           // #5BEFA0

    static func title(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// The glowing night behind every screen.
struct NightBackground: View {
    var body: some View {
        ZStack {
            Theme.night
            RadialGradient(colors: [Theme.blue.opacity(0.5), .clear], center: UnitPoint(x: 1.05, y: -0.05), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Theme.violet.opacity(0.32), .clear], center: UnitPoint(x: -0.1, y: 0.78), startRadius: 0, endRadius: 300)
            RadialGradient(colors: [Theme.green.opacity(0.18), .clear], center: UnitPoint(x: 1.1, y: 0.95), startRadius: 0, endRadius: 260)
        }
        .ignoresSafeArea()
    }
}

/// Frosted glass panel: white 6% over a blur, a thin light border.
struct Glass: ViewModifier {
    var radius: CGFloat = 20
    var border = Color.white.opacity(0.12)
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }
}

extension View {
    func glass(_ radius: CGFloat = 20, border: Color = Color.white.opacity(0.12)) -> some View { modifier(Glass(radius: radius, border: border)) }
}

/// Kimy's body from the design (SVG path in a 200×200 box), scaled into any rect.
struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        // the body spans x 48…152, y 46…160 of the drawing
        let sx = rect.width / 104, sy = rect.height / 114
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + (x - 48) * sx, y: rect.minY + (y - 46) * sy) }
        var path = Path()
        path.move(to: p(48, 146))
        path.addLine(to: p(48, 100))
        path.addCurve(to: p(100, 46), control1: p(48, 68), control2: p(71, 46))
        path.addCurve(to: p(152, 100), control1: p(129, 46), control2: p(152, 68))
        path.addLine(to: p(152, 146))
        path.addCurve(to: p(137, 152), control1: p(152, 156), control2: p(143, 160))
        path.addCurve(to: p(119, 152), control1: p(132, 145), control2: p(124, 145))
        path.addCurve(to: p(100, 152), control1: p(114, 160), control2: p(105, 160))
        path.addCurve(to: p(81, 152), control1: p(95, 145), control2: p(86, 145))
        path.addCurve(to: p(62, 152), control1: p(76, 160), control2: p(67, 160))
        path.addCurve(to: p(48, 146), control1: p(57, 145), control2: p(48, 156))
        path.closeSubpath()
        return path
    }
}

/// Eyes and smile of a ghost, in the same 104×114 frame as GhostShape.
struct GhostFace: View {
    var blink: CGFloat = 1        // 1 open, 0.1 closed
    var look: CGSize = .zero      // eye shift in drawing units
    var body: some View {
        GeometryReader { g in
            let sx = g.size.width / 104, sy = g.size.height / 114
            ZStack {
                ForEach([86.0, 114.0], id: \.self) { cx in
                    Ellipse().fill(Theme.ink)
                        .frame(width: 10 * sx, height: 14 * sy * blink)
                        .position(x: (cx - 48 + look.width) * sx, y: (92 - 46 + look.height) * sy)
                }
                Path { p in
                    p.move(to: CGPoint(x: (87 - 48) * sx, y: (108 - 46) * sy))
                    p.addQuadCurve(to: CGPoint(x: (113 - 48) * sx, y: (108 - 46) * sy), control: CGPoint(x: (100 - 48) * sx, y: (121 - 46) * sy))
                }
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 5 * sx, lineCap: .round))
            }
        }
    }
}

/// A still sticker ghost: the agents' avatars and the small Kimy in headers.
struct GhostBadge: View {
    var color = Theme.blue
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            GhostShape().fill(color)
            GhostShape().stroke(Color.white, lineWidth: max(2, size / 14))
            GhostFace()
        }
        .frame(width: size, height: size * 114 / 104)
        .accessibilityHidden(true)
    }
}

/// The big animated Kimy: floats, blinks, looks around, glowing edge in the brand colours.
struct KimyHero: View {
    var size: CGFloat = 112
    var listening = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { tl in
            let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
            let float = CGFloat(sin(t * 2 * .pi / 3)) * 8
            let blinkPhase = t.truncatingRemainder(dividingBy: 3) / 3
            let blink: CGFloat = (0.44...0.50).contains(blinkPhase) ? 0.15 : 1
            let lookPhase = t.truncatingRemainder(dividingBy: 6) / 6
            let look = lookPhase < 0.3 ? CGSize.zero : lookPhase < 0.55 ? CGSize(width: 4, height: -2) : lookPhase < 0.75 ? CGSize(width: -4, height: 0) : .zero
            let pulse = 0.78 + 0.22 * sin(t * 2 * .pi / (listening ? 1.2 : 2.4))
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.blue.opacity(0.5), Theme.violet.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: size))
                    .frame(width: size * 1.7, height: size * 1.7)
                    .scaleEffect(0.92 + 0.14 * pulse)
                ZStack {
                    GhostShape()
                        .stroke(AngularGradient(colors: [Theme.blue, Theme.violet, Theme.green, Theme.blue], center: .center, angle: .degrees(t * 60)), lineWidth: size / 8)
                        .blur(radius: size / 18)
                        .opacity(pulse)
                    GhostShape().fill(Theme.blue)
                    GhostShape().stroke(Color.white, lineWidth: size / 18)
                    GhostFace(blink: blink, look: look)
                }
                .frame(width: size, height: size * 114 / 104)
                .offset(y: -float)
                Ellipse().fill(Color.black.opacity(0.6 - 0.25 * Double(float / 8)))
                    .frame(width: size * 0.48 * (1 - 0.3 * float / 8), height: 8)
                    .offset(y: size * 0.68)
            }
        }
        .frame(width: size * 1.7, height: size * 1.7)
        .accessibilityElement()
        .accessibilityLabel(listening ? "Kimy слушает" : "Kimy")
    }
}
