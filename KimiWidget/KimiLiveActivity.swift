import ActivityKit
import SwiftUI
import WidgetKit

@main
struct KimiWidgetBundle: WidgetBundle {
    var body: some Widget { KimiLiveActivity() }
}

/// Kimy, the little ghost, in the Dynamic Island (iPhone 14 Pro and later) and on the lock screen (any iPhone with iOS 16.1+).
struct KimiLiveActivity: Widget {
    private let night = Color(red: 0.086, green: 0.102, blue: 0.227)   // #161A3A, the voice-mode ground

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KimiActivity.self) { context in
            HStack(spacing: 12) {
                kimy(context.state.phase).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kimy").font(.headline)
                    Text(context.state.phase.title).font(.subheadline).opacity(0.8)
                }
                Spacer()
                Text(context.state.since, style: .timer)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
            }
            .padding(14)
            .foregroundColor(.white)
            .activityBackgroundTint(night)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    kimy(context.state.phase).frame(width: 44, height: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Kimy · \(context.state.phase.title)").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.since, style: .timer)
                        .font(.caption.monospacedDigit())
                        .frame(width: 48)
                }
            } compactLeading: {
                kimy(context.state.phase)
            } compactTrailing: {
                Text(context.state.phase == .idle ? "Kimy" : context.state.phase.title)
                    .font(.caption2)
            } minimal: {
                kimy(context.state.phase)
            }
        }
    }

    private func kimy(_ phase: KimiPhase) -> some View {
        Image(phase.image).resizable().scaledToFit().accessibilityLabel("Kimy: \(phase.title)")
    }
}
