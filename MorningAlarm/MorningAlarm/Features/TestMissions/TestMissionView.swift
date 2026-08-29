import SwiftUI

/// A standalone way to try any mission's real UI/logic without configuring
/// or ringing an alarm at all — reachable from the alarm list's toolbar.
///
/// Steps uses its own relaxed test-mode timing (short minimum wait, small
/// target) rather than `MissionCoordinator.makeSession(for:)`'s production
/// `StepMissionRunner` defaults (8s minimum, count from real alarm configs),
/// since waiting 8+ real seconds and racking up 10-50 real steps every time
/// just to check the UI looks right defeats the point of a quick test. QR
/// and chess go through the same session-creation path as a real alarm,
/// since there's no equivalent slow default to work around there.
struct TestMissionView: View {
    @Environment(\.dismiss) private var dismiss
    let missionCoordinator: MissionCoordinator
    let stepCounter: StepCounter

    @State private var activeSession: MissionSession?
    @State private var activeTitle = ""

    private static let testStepTarget = 5
    private static let testMinimumElapsedTime: TimeInterval = 2

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startStepsTest()
                    } label: {
                        Label("Steps", systemImage: "figure.walk")
                    }
                    Button {
                        start(title: "QR test", configuration: .qrCode(codeID: nil))
                    } label: {
                        Label("QR Code / Barcode", systemImage: "qrcode")
                    }
                    Button {
                        start(title: "Chess test", configuration: .chessPuzzle(minRating: 600, maxRating: 900, puzzleCount: 1))
                    } label: {
                        Label("Chess Puzzle", systemImage: "checkerboard.rectangle")
                    }
                } footer: {
                    Text("Steps here uses a relaxed test mode — \(Self.testStepTarget) steps, \(Int(Self.testMinimumElapsedTime))s minimum — instead of the real 10-50 steps / 8s an actual alarm uses, so you don't have to wait as long to check it works.")
                }
            }
            .navigationTitle("Test a Mission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { activeSession != nil },
            set: { isPresented in if !isPresented { activeSession = nil } }
        )) {
            if let activeSession {
                MissionView(
                    title: activeTitle,
                    subtitle: activeSession.configuration.summary,
                    session: activeSession,
                    onFinished: { _ in self.activeSession = nil }
                ) {
                    missionCoordinator.contentView(for: activeSession)
                }
            }
        }
    }

    private func startStepsTest() {
        activeTitle = "Steps test"
        let configuration = MissionConfiguration.steps(count: Self.testStepTarget)
        let runner = StepMissionRunner(
            targetSteps: Self.testStepTarget,
            stepCounter: stepCounter,
            minimumElapsedTime: Self.testMinimumElapsedTime
        )
        activeSession = MissionSession(configuration: configuration, runner: runner)
    }

    private func start(title: String, configuration: MissionConfiguration) {
        activeTitle = title
        activeSession = missionCoordinator.makeSession(for: configuration)
    }
}
