import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// What Kimi is doing right now: the app sets it, the Dynamic Island and the lock screen show it.
enum KimiPhase: String, Codable, Hashable {
    case idle, listening, thinking, speaking

    var title: String {
        switch self {
        case .idle: return "На связи"
        case .listening: return "Слушаю…"
        case .thinking: return "Думаю…"
        case .speaking: return "Отвечаю…"
        }
    }

    /// Image set in KimiWidget/Assets.xcassets, drawn by tools/kimy.py.
    var image: String { "kimy-\(rawValue)" }
}

#if canImport(ActivityKit)
/// Kimy's Live Activity (iOS 16.1+): the little ghost in the Dynamic Island and on the lock screen.
@available(iOS 16.1, *)
struct KimiActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: KimiPhase
        var since: Date
    }
}
#endif
