import SwiftUI

@main
struct MorningAlarmApp: App {
    private let container = AppDependencyContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView(
                coordinator: container.alarmCoordinator,
                missionCoordinator: container.missionCoordinator,
                qrCodeRepository: container.qrCodeRepository
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

    var body: some View {
        ZStack {
            AlarmListView(coordinator: coordinator, qrCodeRepository: qrCodeRepository)

            runtimeOverlay
                .zIndex(1)

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
