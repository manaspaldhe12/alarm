import SwiftUI

@main
struct MorningAlarmApp: App {
    private let container = AppDependencyContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: container.alarmCoordinator)
                .task {
                    await container.alarmCoordinator.start()
                }
        }
    }
}

struct RootView: View {
    @Bindable var coordinator: AlarmCoordinator

    var body: some View {
        ZStack {
            AlarmListView(coordinator: coordinator)

            if case .ringing(let alarmID) = coordinator.runtimeState,
               let alarm = coordinator.alarm(for: alarmID) {
                AlarmRingingView(
                    alarm: alarm,
                    onSnooze: {
                        Task { await coordinator.snoozeCurrentAlarm() }
                    },
                    onTurnOff: {
                        Task { await coordinator.turnOffCurrentAlarm() }
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut, value: coordinator.runtimeState)
    }
}
