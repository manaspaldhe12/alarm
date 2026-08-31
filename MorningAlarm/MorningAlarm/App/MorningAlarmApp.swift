import SwiftUI

@main
struct MorningAlarmApp: App {
    private let container = AppDependencyContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: container.alarmCoordinator,
                missionCoordinator: container.missionCoordinator,
                qrCodeRepository: container.qrCodeRepository,
                stepCounter: container.stepCounter,
                puzzleLibrary: container.puzzleLibrary
            )
            .task {
                await container.alarmCoordinator.start()
            }
        }
    }
}

struct RootView: View {
    @Bindable var coordinator: AlarmCoordinator
    let missionCoordinator: MissionCoordinator
    let qrCodeRepository: QRCodeRepository
    let stepCounter: StepCounter
    let puzzleLibrary: BundledPuzzleRepository

    var body: some View {
        ZStack {
            AlarmListView(
                coordinator: coordinator,
                qrCodeRepository: qrCodeRepository,
                missionCoordinator: missionCoordinator,
                stepCounter: stepCounter,
                puzzleLibrary: puzzleLibrary
            )

            runtimeOverlay
                .zIndex(1)

            // Turning the volume down is otherwise a trivial way to defeat
            // a mission-gated alarm — see VolumeForcer's doc comment. Not
            // active during .gentleWake (that's a deliberate soft ramp) or
            // once the mission is actually done (.snoozed/.morningComplete)
            // -- only while the alarm is genuinely still going/being fought.
            VolumeForcer(isActive: shouldForceMaxVolume)
                .frame(width: 0, height: 0)

            if let wakeAlarmID = coordinator.wakeUpCoordinator.activeAlarmID,
               let wakeAlarm = coordinator.alarm(for: wakeAlarmID) {
                WakeUpCheckView(
                    alarm: wakeAlarm,
                    wakeUpCoordinator: coordinator.wakeUpCoordinator,
                    missionCoordinator: missionCoordinator
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut, value: coordinator.runtimeState)
    }

    private var shouldForceMaxVolume: Bool {
        switch coordinator.runtimeState {
        case .ringing, .runningMission:
            return true
        case .idle, .gentleWake, .snoozed, .morningComplete:
            return coordinator.wakeUpCoordinator.activeAlarmID != nil
        }
    }

    @ViewBuilder
    private var runtimeOverlay: some View {
        switch coordinator.runtimeState {
        case .idle, .gentleWake:
            EmptyView()

        case .ringing(let alarmID):
            if let alarm = coordinator.alarm(for: alarmID) {
                AlarmRingingView(
                    alarm: alarm,
                    onSnooze: { coordinator.beginSnooze() },
                    onTurnOff: { coordinator.beginTurnOff() }
                )
                .transition(.opacity)
            }

        case .runningMission(_, let action):
            if let session = coordinator.currentMissionSession {
                MissionView(
                    title: action == .snooze ? "Let's get moving" : "You're almost there",
                    subtitle: session.configuration.summary,
                    session: session,
                    onFinished: { result in coordinator.missionFinished(result) }
                ) {
                    missionCoordinator.contentView(for: session)
                }
                .transition(.opacity)
            }

        case .snoozed(let until, _):
            SnoozedConfirmationView(until: until, quote: coordinator.currentQuote) {
                coordinator.acknowledgeSnoozeConfirmation()
            }
            .transition(.opacity)

        case .morningComplete(let alarmID):
            if let alarm = coordinator.alarm(for: alarmID) {
                MorningCompleteView(
                    quote: coordinator.currentQuote,
                    postAlarmAction: alarm.postAlarmAction,
                    onOpenApp: {
                        Task { await coordinator.appLauncher.open(alarm.postAlarmAction) }
                    },
                    onDone: { coordinator.finishMorningComplete() }
                )
                .transition(.opacity)
            }
        }
    }
}
