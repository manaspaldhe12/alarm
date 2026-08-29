import XCTest
@testable import MorningAlarm

@MainActor
final class WakeUpCoordinatorTests: XCTestCase {
    func makeCoordinator(scheduler: FakeAlarmScheduler, fileURL: URL? = nil) -> WakeUpCoordinator {
        let missionCoordinator = MissionCoordinator(
            stepCounter: FakeStepCounter(),
            qrCodeRepository: FakeQRCodeRepository(),
            puzzleRepository: FakePuzzleRepository(),
            chessEngine: LocalChessEngine()
        )
        return WakeUpCoordinator(
            scheduler: scheduler,
            missionCoordinator: missionCoordinator,
            stateStore: WakeUpCheckStateStore(fileURL: fileURL ?? tempFileURL("wakeup"))
        )
    }

    func testScheduleIgnoresDisabledCheck() async {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: false, delayMinutes: 15, mission: .steps(count: 50))

        await coordinator.schedule(for: alarm)
        XCTAssertEqual(scheduler.scheduledCalls.count, 0, "a disabled wake-up check should never call the scheduler")
    }

    func testScheduleRegistersPendingCheckAndCallsScheduler() async throws {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))

        await coordinator.schedule(for: alarm)

        XCTAssertEqual(scheduler.scheduledCalls.count, 1)
        XCTAssertEqual(coordinator.pendingCheckIDs.count, 1)
        let checkID = try XCTUnwrap(coordinator.pendingCheckIDs.keys.first)
        XCTAssertEqual(coordinator.pendingCheckIDs[checkID], alarm.id)
        XCTAssertEqual(scheduler.scheduledCalls.first?.alarm.id, checkID, "the scheduled synthetic alarm's id must be the check id, not the original alarm's id")
        XCTAssertNotNil(scheduler.scheduledCalls.first?.fireDate)
    }

    func testCancelPendingRemovesOnlyMatchingAlarm() async {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        var alarmA = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarmA.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        var alarmB = Alarm(time: LocalTime(hour: 8, minute: 0))
        alarmB.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))

        await coordinator.schedule(for: alarmA)
        await coordinator.schedule(for: alarmB)
        XCTAssertEqual(coordinator.pendingCheckIDs.count, 2)

        await coordinator.cancelPending(forOriginalAlarmID: alarmA.id)

        XCTAssertEqual(coordinator.pendingCheckIDs.count, 1)
        XCTAssertEqual(coordinator.pendingCheckIDs.values.first, alarmB.id)
        XCTAssertEqual(scheduler.cancelledIDs.count, 1)
        // stop() before cancel(): every check alarm is non-repeating, the exact case
        // AlarmCoordinator's own belt-and-suspenders comment says needs both, not cancel() alone.
        XCTAssertEqual(scheduler.stoppedIDs.count, 1, "cancelPending should stop() a possibly-alerting check alarm too, not just cancel() it")
    }

    func testPollTransitionsActiveAlarmIDWhenCheckAlerts() async throws {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        await coordinator.schedule(for: alarm)

        let checkID = try XCTUnwrap(coordinator.pendingCheckIDs.keys.first)
        scheduler.alerting = [checkID]

        XCTAssertNil(coordinator.activeAlarmID)
        await coordinator.poll()

        XCTAssertEqual(coordinator.activeAlarmID, alarm.id)
        XCTAssertEqual(scheduler.stoppedIDs, [checkID], "poll should formally stop the AlarmKit alert once captured")
        // Every check alarm is non-repeating -- exactly the case that needs cancel() too, per the
        // same documented-AlarmKit-bug reasoning AlarmCoordinator.performTurnOff already applies.
        XCTAssertEqual(scheduler.cancelledIDs, [checkID], "poll should also cancel() a fired non-repeating check alarm, not just stop() it")
        XCTAssertEqual(coordinator.pendingCheckIDs.count, 0, "the consumed check should be removed from pending state")
    }

    func testPollIgnoresUnrelatedAlertingIDs() async {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        scheduler.alerting = [UUID()] // some other, unrelated alarm

        await coordinator.poll()
        XCTAssertNil(coordinator.activeAlarmID)
    }

    func testBeginMissionOnlyWorksWhileActive() {
        let coordinator = makeCoordinator(scheduler: FakeAlarmScheduler())
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))

        coordinator.beginMission(for: alarm)
        XCTAssertNil(coordinator.missionSession, "should not start a mission session with no active check")
    }

    func testMissionFinishedClearsState() async throws {
        let scheduler = FakeAlarmScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        await coordinator.schedule(for: alarm)
        let checkID = try XCTUnwrap(coordinator.pendingCheckIDs.keys.first)
        scheduler.alerting = [checkID]
        await coordinator.poll()

        coordinator.beginMission(for: alarm)
        XCTAssertNotNil(coordinator.missionSession)

        coordinator.missionFinished(.completed)
        XCTAssertNil(coordinator.missionSession)
        XCTAssertNil(coordinator.activeAlarmID)
    }

    func testStatePersistsAcrossCoordinatorInstances() async throws {
        let fileURL = tempFileURL("wakeup-persist")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let scheduler = FakeAlarmScheduler()

        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))

        let first = makeCoordinator(scheduler: scheduler, fileURL: fileURL)
        await first.start()
        await first.schedule(for: alarm)
        let checkID = try XCTUnwrap(first.pendingCheckIDs.keys.first)

        // Simulate app relaunch: a brand new coordinator instance backed by the same file.
        let second = makeCoordinator(scheduler: scheduler, fileURL: fileURL)
        await second.start()
        XCTAssertEqual(second.pendingCheckIDs[checkID], alarm.id, "pending checks must survive app relaunch")
    }
}
