import AlarmKit
import ActivityKit
import SwiftUI
import WidgetKit

struct MorningAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MorningAlarmMetadata>.self) { context in
            MorningAlarmLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.metadata?.label ?? "Alarm")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    switch context.state.mode {
                    case .countdown(let countdown):
                        Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                            .monospacedDigit()
                    case .alert:
                        Text("Now")
                    case .paused:
                        Text("Paused")
                    @unknown default:
                        EmptyView()
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                switch context.state.mode {
                case .countdown(let countdown):
                    Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                        .monospacedDigit()
                default:
                    Image(systemName: "bell.fill")
                }
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}

private struct MorningAlarmLockScreenView: View {
    let context: ActivityViewContext<AlarmAttributes<MorningAlarmMetadata>>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.metadata?.label ?? "Morning Alarm")
                    .font(.headline)
                switch context.state.mode {
                case .countdown:
                    Text("Snoozing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .alert:
                    Text("Good morning")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .paused:
                    Text("Paused")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                @unknown default:
                    EmptyView()
                }
            }

            Spacer()

            switch context.state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                    .font(.title2.monospacedDigit())
            case .alert:
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            case .paused:
                Image(systemName: "pause.fill")
                    .font(.title2)
            @unknown default:
                EmptyView()
            }
        }
        .padding()
    }
}
