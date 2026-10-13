import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Keeps Kimi in the Dynamic Island and on the lock screen while the app is open or minimised.
/// iOS 15 and phones without Live Activities simply get nothing; the app works the same.
/// shortcut: updates come only from the running app (no push: that needs a paid Apple developer account);
/// once the app is suspended the island keeps the last state and its timer. Upgrade to APNs push updates
/// when there is a paid account.
@MainActor
final class Island {
    static let shared = Island()
    private var last: KimiPhase?

    func show(_ phase: KimiPhase) {
        guard phase != last else { return }
        last = phase
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) { Self.apply(phase) }
        #endif
    }

    /// Called when the app comes back: iOS ends a Live Activity after about 8 hours, this starts a new one.
    func refresh(_ phase: KimiPhase) {
        last = nil
        show(phase)
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static func apply(_ phase: KimiPhase) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = KimiActivity.ContentState(phase: phase, since: Date())
        let running = Activity<KimiActivity>.activities.filter { $0.activityState == .active }
        if let current = running.first {
            for extra in running.dropFirst() {   // only one Kimy at a time
                Task { await extra.end(dismissalPolicy: .immediate) }
            }
            Task { await current.update(using: state) }
        } else {
            // fails only when Live Activities are off or the system refuses: the chat keeps working regardless
            _ = try? Activity.request(attributes: KimiActivity(), contentState: state, pushType: nil)
        }
    }
    #endif
}
