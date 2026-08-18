import SwiftUI

struct AlarmRingingView: View {
    let alarm: Alarm
    let onSnooze: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.35), Color.yellow.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text("☀️ Good morning")
                        .font(.title2.weight(.semibold))

                    Text(alarm.time.formatted)
                        .font(.system(size: 72, weight: .thin, design: .rounded))
                        .monospacedDigit()

                    Text(alarm.label)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(action: onSnooze) {
                        Text("Snooze")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button(action: onTurnOff) {
                        Text("Turn Off")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    AlarmRingingView(
        alarm: Alarm(time: LocalTime(hour: 7, minute: 0)),
        onSnooze: {},
        onTurnOff: {}
    )
}
