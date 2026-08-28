import Foundation

@MainActor
struct AppDependencyContainer {
    let alarmCoordinator: AlarmCoordinator
    let missionCoordinator: MissionCoordinator
    let qrCodeRepository: QRCodeRepository
    let stepCounter: StepCounter

    static func make() -> AppDependencyContainer {
        let repository = FileAlarmRepository()
        let scheduler = AlarmKitScheduler()
        let audioPlayer = LocalAlarmAudioPlayer()

        let qrCodeRepository = FileQRCodeRepository()
        let puzzleRepository = BundledPuzzleRepository()
        let chessEngine = LocalChessEngine()
        let stepCounter = PedometerStepCounter()

        let missionCoordinator = MissionCoordinator(
            stepCounter: stepCounter,
            qrCodeRepository: qrCodeRepository,
            puzzleRepository: puzzleRepository,
            chessEngine: chessEngine
        )

        let quoteCoordinator = QuoteCoordinator(repository: BundledQuoteRepository())

        let wakeUpCoordinator = WakeUpCoordinator(
            scheduler: scheduler,
            missionCoordinator: missionCoordinator,
            stateStore: WakeUpCheckStateStore()
        )

        let appLauncher = SystemExternalAppLauncher()

        let coordinator = AlarmCoordinator(
            repository: repository,
            scheduler: scheduler,
            audioPlayer: audioPlayer,
            missionCoordinator: missionCoordinator,
            quoteCoordinator: quoteCoordinator,
            wakeUpCoordinator: wakeUpCoordinator,
            appLauncher: appLauncher
        )

        return AppDependencyContainer(
            alarmCoordinator: coordinator,
            missionCoordinator: missionCoordinator,
            qrCodeRepository: qrCodeRepository,
            stepCounter: stepCounter
        )
    }
}
