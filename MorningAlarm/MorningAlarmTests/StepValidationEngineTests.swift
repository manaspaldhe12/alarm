import XCTest
@testable import MorningAlarm

final class StepValidationEngineTests: XCTestCase {
    func testAcceptsGenuineWalkingPace() {
        var engine = StepValidationEngine(minimumElapsedTime: 5, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)

        // Baseline reading establishes the starting cumulative count.
        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        // ~2 steps/second — well within a plausible walking cadence.
        let accepted = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(5), cumulativeSteps: 10))
        XCTAssertEqual(accepted, 10, "plausible walking cadence should be fully accepted")
    }

    func testRejectsImplausibleShakeBurst() {
        var engine = StepValidationEngine(minimumElapsedTime: 5, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)

        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        // 50 "steps" in 0.5s = 100 steps/sec — way past any plausible walking cadence.
        let accepted = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(0.5), cumulativeSteps: 50))
        XCTAssertEqual(accepted, 0, "an implausibly fast burst should be rejected, not counted")
    }

    func testDoesNotCompleteBeforeMinimumElapsedTime() {
        var engine = StepValidationEngine(minimumElapsedTime: 30, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)
        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        // 50 steps over 15s = ~3.3/s, comfortably under the 4/s cap so this is purely
        // testing the elapsed-time gate, not the cadence gate.
        _ = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(15), cumulativeSteps: 50))

        XCTAssertFalse(engine.isComplete(target: 50, now: start.addingTimeInterval(15)), "should not complete before minimumElapsedTime has passed even if steps are already met")
        XCTAssertTrue(engine.isComplete(target: 50, now: start.addingTimeInterval(31)), "should complete once both steps and elapsed time requirements are met")
    }

    func testDoesNotCompleteWithoutEnoughSteps() {
        var engine = StepValidationEngine(minimumElapsedTime: 1, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)
        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        _ = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(10), cumulativeSteps: 20))

        XCTAssertFalse(engine.isComplete(target: 50, now: start.addingTimeInterval(10)))
    }

    func testAcceptedStepsNeverDecreaseAcrossRejectedBatches() {
        var engine = StepValidationEngine(minimumElapsedTime: 1, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)
        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        _ = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(5), cumulativeSteps: 10))
        // A later burst that's implausibly fast relative to the *previous* reading should be
        // rejected without discarding the steps already accepted.
        let accepted = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(5.1), cumulativeSteps: 60))
        XCTAssertEqual(accepted, 10, "a rejected burst should not erase previously accepted steps")
    }

    func testIgnoresNonIncreasingCumulativeCounts() {
        var engine = StepValidationEngine(minimumElapsedTime: 1, maximumStepsPerSecond: 4.0)
        let start = Date()
        engine.start(at: start)
        _ = engine.accept(StepUpdate(timestamp: start, cumulativeSteps: 0))
        // 3 steps/second — within the 4/s cap.
        let afterIncrease = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(1), cumulativeSteps: 3))
        XCTAssertEqual(afterIncrease, 3)
        // Pedometer resets/duplicates sometimes report an equal or lower cumulative count.
        let afterStale = engine.accept(StepUpdate(timestamp: start.addingTimeInterval(2), cumulativeSteps: 3))
        XCTAssertEqual(afterStale, 3, "a non-increasing reading should be ignored, not reduce accepted steps")
    }
}
