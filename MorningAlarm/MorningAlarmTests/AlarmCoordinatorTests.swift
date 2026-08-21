import XCTest
@testable import MorningAlarm

@MainActor
final class AlarmCoordinatorTests: XCTestCase {
    struct Harness {
        let coordinator: AlarmCoordinator
        let scheduler: FakeAlarmScheduler
        let audioPlayer: FakeAlarmAudioPlayer
        let repository: FakeAlarmRepository
        let appLauncher: FakeExternalAppLauncher
    }

    func makeHarness(quotes: [Quote] = [Quote(id: "q1", text: "Get up.", category: .general)]) -> Harness {
        let scheduler = FakeAlarmScheduler()
        let audioPlayer = FakeAlarmAudioPlayer()
        let repository = FakeAlarmRepository()
        let appLauncher = FakeExternalAppLauncher()

        let missionCoordinator = MissionCoordinator(
            stepCounter: FakeStepCounter(),
            qrCodeRepository: FakeQRCodeRepository(),
            puzzleRepository: FakePuzzleRepository(),
            chessEngine: LocalChessEngine()
        )
        let quoteCoordinator = QuoteCoordinator(repository: FakeQuoteRepository(quotes: quotes))
        let wakeUpCoordinator = WakeUpCoordinator(
            scheduler: scheduler,
            missionCoordinator: missionCoordinator,
            stateStore: WakeUpCheckStateStore(fileURL: tempFileURL("wakeup-in-alarm-test"))
        )

        let coordinator = AlarmCoordinator(
            repository: repository,
            scheduler: scheduler,
            audioPlayer: audioPlayer,
            missionCoordinator: missionCoordinator,
            quoteCoordinator: quoteCoordinator,
            wakeUpCoordinator: wakeUpCoordinator,
            appLauncher: appLauncher
        )

        return Harness(coordinator: coordinator, scheduler: scheduler, audioPlayer: audioPlayer, repository: repository, appLauncher: appLauncher)
    }

    /// Waits for a `.runningMission` state's mission session to resolve (used for `.none`
    /// missions, which resolve almost instantly via `NoMissionRunner`). In the real app,
    /// `MissionView`'s `.task { session.start() }` is what kicks the session off; there's
    /// no view here, so this starts it explicitly first.
    func waitForMissionResult(_ h: Harness) async throws {
        h.coordinator.currentMissionSession?.start()
        for _ in 0..<80 {
            guard case .runningMission = h.coordinator.runtimeState else {
                // missionFinished's own follow-up (performSnooze/performTurnOff) runs in a
                // detached Task, so the state transition out of .runningMission happens
                // asynchronously even after missionFinished(_:) has been called below —
                // keep polling until that's actually landed, not just until it's kicked off.
                return
            }
            if let result = h.coordinator.currentMissionSession?.result {
                h.coordinator.missionFinished(result)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("timed out waiting for mission to resolve")
    }

    func testCreateAlarmSchedulesWhenAuthorized() async {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        await h.coordinator.createAlarm(at: LocalTime(hour: 7, minute: 0), label: "Wake up")

        XCTAssertEqual(h.coordinator.alarms.count, 1)
        XCTAssertEqual(h.scheduler.scheduledCalls.count, 1)
        XCTAssertNil(h.scheduler.scheduledCalls.first?.fireDate, "a fresh alarm should be scheduled via the scheduler's own recurrence logic (fireDate: nil), not a manually computed date")
    }

    func testCreateAlarmFailsGracefullyWhenUnauthorized() async {
        let h = makeHarness()
        h.scheduler.authorizationResult = false
        await h.coordinator.refreshAuthorization()
        await h.coordinator.createAlarm(at: LocalTime(hour: 7, minute: 0))

        XCTAssertEqual(h.coordinator.alarms.count, 1, "the alarm should still be saved locally even if scheduling authorization is denied")
        XCTAssertEqual(h.scheduler.scheduledCalls.count, 0)
        XCTAssertNotNil(h.coordinator.lastErrorMessage)
    }

    func testPresentRingingAlarmPlaysSound() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        await h.coordinator.createAlarm(at: LocalTime(hour: 7, minute: 0))
        let alarmID = try XCTUnwrap(h.coordinator.alarms.first?.id)

        await h.coordinator.presentRingingAlarm(alarmID)

        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarmID))
        XCTAssertEqual(h.audioPlayer.playedSounds.count, 1)
    }

    func testBeginSnoozeRunsMissionThenSnoozesAndShowsQuote() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.snooze = SnoozeConfiguration(durationMinutes: 10, mission: .none, maxSnoozes: nil)
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginSnooze()
        XCTAssertEqual(h.coordinator.runtimeState, .runningMission(alarmID: alarm.id, action: .snooze))
        // startMission stops the audio player via a detached, fire-and-forget Task (so
        // beginSnooze/beginTurnOff can stay synchronous for plain SwiftUI button actions) —
        // give it a beat to actually run before asserting on it.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(h.audioPlayer.stopCount, 1, "the alarm sound should stop while a mission is in progress")

        try await waitForMissionResult(h)

        guard case .snoozed(let until, let snoozedAlarmID) = h.coordinator.runtimeState else {
            XCTFail("expected .snoozed, got \(h.coordinator.runtimeState)")
            return
        }
        XCTAssertEqual(snoozedAlarmID, alarm.id)
        XCTAssertGreaterThan(until, Date())
        XCTAssertNotNil(h.coordinator.currentQuote, "a quote should be shown after a successful snooze")
        XCTAssertEqual(h.scheduler.scheduledCalls.last?.alarm.id, alarm.id)
        XCTAssertNotNil(h.scheduler.scheduledCalls.last?.fireDate, "snoozing must use a one-shot fireDate override, not the alarm's own recurring schedule")
    }

    func testMaxSnoozesForcesTurnOffMission() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.snooze = SnoozeConfiguration(durationMinutes: 10, mission: .none, maxSnoozes: 1)
        alarm.turnOffMission = .none
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        // First snooze should succeed normally.
        h.coordinator.beginSnooze()
        try await waitForMissionResult(h)
        guard case .snoozed = h.coordinator.runtimeState else {
            XCTFail("expected .snoozed after the first (allowed) snooze")
            return
        }

        // Re-ring, then a second snooze attempt should redirect straight to the turn-off mission.
        await h.coordinator.presentRingingAlarm(alarm.id)
        h.coordinator.beginSnooze()
        XCTAssertEqual(h.coordinator.runtimeState, .runningMission(alarmID: alarm.id, action: .turnOff), "exceeding maxSnoozes should redirect to the turn-off mission, not snooze again")
    }

    func testTurnOffOnRepeatingAlarmReschedulesNatively() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0), recurrence: Recurrence.everyDay)
        alarm.turnOffMission = .none
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        try await waitForMissionResult(h)

        guard case .morningComplete(let completedID) = h.coordinator.runtimeState else {
            XCTFail("expected .morningComplete, got \(h.coordinator.runtimeState)")
            return
        }
        XCTAssertEqual(completedID, alarm.id)

        let reloaded = try XCTUnwrap(h.coordinator.alarm(for: alarm.id))
        XCTAssertTrue(reloaded.enabled, "a repeating alarm should remain enabled after turn-off")
        XCTAssertEqual(h.scheduler.scheduledCalls.last?.alarm.id, alarm.id)
        XCTAssertNil(h.scheduler.scheduledCalls.last?.fireDate, "turning off a repeating alarm should reinstall its native recurring schedule (fireDate: nil)")
    }

    func testTurnOffOnOneTimeAlarmDisablesIt() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0)) // .never recurrence by default
        alarm.turnOffMission = .none
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        try await waitForMissionResult(h)

        let reloaded = try XCTUnwrap(h.coordinator.alarm(for: alarm.id))
        XCTAssertFalse(reloaded.enabled, "a one-time alarm should disable itself after firing")
    }

    func testTurnOffSchedulesWakeUpCheckWhenEnabled() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .none
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        try await waitForMissionResult(h)

        XCTAssertEqual(h.coordinator.wakeUpCoordinator.pendingCheckIDs.count, 1, "turning off should schedule a wake-up check when enabled")
    }

    func testMissionCancelledReturnsToRingingAndResumesSound() async {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .steps(count: 999_999) // never completes on its own
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        XCTAssertEqual(h.coordinator.runtimeState, .runningMission(alarmID: alarm.id, action: .turnOff))

        h.coordinator.currentMissionSession?.cancel()
        h.coordinator.missionFinished(.cancelled)

        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarm.id))
        XCTAssertEqual(h.audioPlayer.playedSounds.count, 2, "cancelling a mission should resume the alarm sound (played once on ring, once on resume)")
    }

    func testDeleteAlarmCancelsSchedulerAndPendingWakeUpCheck() async {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.wakeUpCoordinator.schedule(for: alarm)
        XCTAssertEqual(h.coordinator.wakeUpCoordinator.pendingCheckIDs.count, 1)

        await h.coordinator.deleteAlarm(id: alarm.id)

        XCTAssertEqual(h.coordinator.alarms.count, 0)
        XCTAssertTrue(h.scheduler.cancelledIDs.contains(alarm.id))
        XCTAssertEqual(h.coordinator.wakeUpCoordinator.pendingCheckIDs.count, 0, "deleting an alarm should cancel its pending wake-up check too")
    }

    func testSyncAlertingAlarmsTransitionsGentleWakeThenRinging() async {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.gentleWake = GentleWakeConfiguration(enabled: true, durationMinutes: 10)
        await h.coordinator.updateAlarm(alarm)

        h.scheduler.countdown = [alarm.id]
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .gentleWake(alarmID: alarm.id))
        XCTAssertEqual(h.audioPlayer.playedGentleWakeSounds.count, 1)

        h.scheduler.countdown = []
        h.scheduler.alerting = [alarm.id]
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarm.id))
        XCTAssertEqual(h.audioPlayer.playedSounds.count, 1, "the full alarm sound should play once ringing starts")
    }

    func testSyncAlertingAlarmsIgnoresUnknownIDs() async {
        let h = makeHarness()
        h.scheduler.alerting = [UUID()] // e.g. a wake-up-check ID, not a real alarm
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .idle)
    }

    func testSetEnabledFalseCancelsPendingWakeUpCheck() async {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.wakeUpCheck = WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50))
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.wakeUpCoordinator.schedule(for: alarm)
        XCTAssertEqual(h.coordinator.wakeUpCoordinator.pendingCheckIDs.count, 1)

        await h.coordinator.setEnabled(false, for: alarm.id)

        XCTAssertEqual(h.coordinator.wakeUpCoordinator.pendingCheckIDs.count, 0)
        XCTAssertFalse(h.coordinator.alarm(for: alarm.id)?.enabled ?? true)
    }

    func testFinishMorningCompleteReturnsToIdle() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .none
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)
        h.coordinator.beginTurnOff()
        try await waitForMissionResult(h)

        guard case .morningComplete = h.coordinator.runtimeState else {
            XCTFail("expected .morningComplete")
            return
        }

        h.coordinator.finishMorningComplete()
        XCTAssertEqual(h.coordinator.runtimeState, .idle)
        XCTAssertNil(h.coordinator.currentQuote)
    }
}
