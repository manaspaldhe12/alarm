import XCTest
@testable import MorningAlarm

@MainActor
final class MissionCoordinatorTests: XCTestCase {
    func makeCoordinator(stepCounter: StepCounter = FakeStepCounter()) -> MissionCoordinator {
        MissionCoordinator(
            stepCounter: stepCounter,
            qrCodeRepository: FakeQRCodeRepository(),
            puzzleRepository: FakePuzzleRepository(),
            chessEngine: LocalChessEngine()
        )
    }

    func testMakeSessionDispatchesStepsToARunner() {
        let coordinator = makeCoordinator()
        let session = coordinator.makeSession(for: .steps(count: 10))
        XCTAssertEqual(session.configuration, .steps(count: 10))
        XCTAssertNil(session.result)
    }

    func testMakeSessionForQRAndChessCarriesNoRunner() {
        let coordinator = makeCoordinator()
        let qrSession = coordinator.makeSession(for: .qrCode(codeID: nil))
        let chessSession = coordinator.makeSession(for: .chessPuzzle(minRating: 600, maxRating: 800, puzzleCount: 1))

        // Interactive missions never resolve on their own — calling start() must be a
        // harmless no-op since there's no runner to drive.
        qrSession.start()
        chessSession.start()
        XCTAssertNil(qrSession.result)
        XCTAssertNil(chessSession.result)
    }

    func testStepMissionRunsEndToEndAndCompletes() async throws {
        // Exercises the real StepMissionRunner + StepValidationEngine pipeline end to end,
        // through a real AsyncStream, with real (short) wall-clock delays between updates —
        // MissionConfiguration/MissionCoordinator don't expose overriding the runner's
        // production 8-second minimumElapsedTime default, so this constructs the runner
        // directly with a short one purely to keep the test fast; the logic under test
        // (accept/isComplete) is identical either way.
        let stepCounter = FakeStepCounter()
        stepCounter.realDelayBetweenUpdatesNanoseconds = 60_000_000 // 60ms
        let start = Date()
        stepCounter.scriptedUpdates = (0...10).map { i in
            StepUpdate(timestamp: start.addingTimeInterval(Double(i) * 0.06), cumulativeSteps: i)
        }

        let runner = StepMissionRunner(targetSteps: 10, stepCounter: stepCounter, minimumElapsedTime: 0.3, maximumStepsPerSecond: 100)
        let result = await runner.run { _ in }

        XCTAssertEqual(result, .completed)
    }

    func testStepMissionFailsWhenCounterUnavailable() async {
        let stepCounter = FakeStepCounter()
        stepCounter.available = false
        let runner = StepMissionRunner(targetSteps: 10, stepCounter: stepCounter)
        let result = await runner.run { _ in }

        guard case .failed = result else {
            XCTFail("expected .failed when the step counter reports unavailable, got \(result)")
            return
        }
    }

    func testInteractiveSessionCanBeCompletedManually() {
        let coordinator = makeCoordinator()
        let session = coordinator.makeSession(for: .qrCode(codeID: nil))
        session.updateProgress(MissionProgress(fraction: 0.5, statusText: "scanning"))
        XCTAssertEqual(session.progress.fraction, 0.5)
        session.complete()
        XCTAssertEqual(session.result, .completed)
    }

    func testCancelSetsCancelledResult() {
        let coordinator = makeCoordinator()
        let session = coordinator.makeSession(for: .qrCode(codeID: nil))
        session.cancel()
        XCTAssertEqual(session.result, .cancelled)
    }
}
