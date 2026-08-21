import SwiftUI

/// The single runtime screen used for every mission (snooze, turn-off, and
/// wake-up check). It has no idea which concrete mission is running — the
/// caller supplies the matching content view (via `MissionCoordinator`) and
/// this just provides shared chrome and reacts once `session.result`
/// resolves.
struct MissionView<Content: View>: View {
    let title: String
    let subtitle: String
    let session: MissionSession
    let onFinished: (MissionResult) -> Void
    let content: Content

    init(
        title: String,
        subtitle: String,
        session: MissionSession,
        onFinished: @escaping (MissionResult) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.session = session
        self.onFinished = onFinished
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.3), Color.yellow.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Spacer()

                content

                Spacer()

                Button("Cancel", role: .cancel) {
                    session.cancel()
                }
                .padding(.bottom, 32)
            }
        }
        .task { session.start() }
        .onChange(of: session.result) { _, newValue in
            if let newValue {
                onFinished(newValue)
            }
        }
    }
}

struct StepMissionContentView: View {
    let session: MissionSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text(session.progress.statusText)
                .font(.title.weight(.medium).monospacedDigit())

            ProgressView(value: session.progress.fraction)
                .tint(.orange)
                .padding(.horizontal, 48)
        }
    }
}
