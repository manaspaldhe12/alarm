import SwiftUI

/// Builds sessions and their runtime UI for a `MissionConfiguration` without
/// the rest of the app ever needing to know which concrete mission types
/// exist. New mission types are added here and nowhere else in the
/// presentation layer.
///
/// Step missions run headlessly via a `MissionRunner` (see `MissionSession`).
/// QR and chess missions are interactive — their content view owns a live
/// camera preview / tappable board and calls `session.complete()` /
/// `session.fail(reason:)` directly, so their sessions carry no runner.
@MainActor
final class MissionCoordinator {
    private let stepCounter: StepCounter
    private let qrCodeRepository: QRCodeRepository
    private let puzzleRepository: PuzzleRepository
    private let chessEngine: ChessEngine

    init(
        stepCounter: StepCounter,
        qrCodeRepository: QRCodeRepository,
        puzzleRepository: PuzzleRepository,
        chessEngine: ChessEngine
    ) {
        self.stepCounter = stepCounter
        self.qrCodeRepository = qrCodeRepository
        self.puzzleRepository = puzzleRepository
        self.chessEngine = chessEngine
    }

    func makeSession(for configuration: MissionConfiguration) -> MissionSession {
        switch configuration {
        case .none:
            return MissionSession(configuration: configuration, runner: NoMissionRunner())
        case .steps(let count):
            let runner = StepMissionRunner(targetSteps: count, stepCounter: stepCounter)
            return MissionSession(configuration: configuration, runner: runner)
        case .qrCode, .chessPuzzle:
            return MissionSession(configuration: configuration, runner: nil)
        }
    }

    @ViewBuilder
    func contentView(for session: MissionSession) -> some View {
        switch session.configuration.type {
        case .none:
            ProgressView()
        case .steps:
            StepMissionContentView(session: session)
        case .qrCode:
            QRMissionContentView(session: session, repository: qrCodeRepository)
        case .chessPuzzle:
            ChessMissionContentView(session: session, puzzleRepository: puzzleRepository, engine: chessEngine)
        }
    }
}
