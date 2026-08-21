import SwiftUI

/// Driven entirely by `WakeUpCoordinator`, independent of the main
/// `AlarmCoordinator` runtime state — this can appear well after the
/// original alarm flow has finished.
struct WakeUpCheckView: View {
    let alarm: Alarm
    let wakeUpCoordinator: WakeUpCoordinator
    let missionCoordinator: MissionCoordinator

    var body: some View {
        if let session = wakeUpCoordinator.missionSession {
            MissionView(
                title: "Still up?",
                subtitle: session.configuration.summary,
                session: session,
                onFinished: { result in wakeUpCoordinator.missionFinished(result) }
            ) {
                missionCoordinator.contentView(for: session)
            }
        } else {
            promptView
        }
    }

    private var promptView: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.25), Color.orange.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("Still up?")
                    .font(.largeTitle.weight(.bold))

                Text("Just checking in, \(alarm.label).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    wakeUpCoordinator.beginMission(for: alarm)
                } label: {
                    Text("I'm up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}
