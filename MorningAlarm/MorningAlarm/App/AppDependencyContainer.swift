import Foundation

@MainActor
struct AppDependencyContainer {
    let alarmCoordinator: AlarmCoordinator

    static func make() -> AppDependencyContainer {
        let repository = FileAlarmRepository()
        let scheduler = AlarmKitScheduler()
        let audioPlayer = LocalAlarmAudioPlayer()

        let coordinator = AlarmCoordinator(
            repository: repository,
            scheduler: scheduler,
            audioPlayer: audioPlayer
        )

        return AppDependencyContainer(alarmCoordinator: coordinator)
    }
}
