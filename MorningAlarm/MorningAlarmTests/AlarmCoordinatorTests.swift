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

    func makeHarness(
        quotes: [Quote] = [Quote(id: "q1", text: "Get up.", category: .general)],
        stepCounter: StepCounter = FakeStepCounter()
    ) -> Harness {
        let scheduler = FakeAlarmScheduler()
        let audioPlayer = FakeAlarmAudioPlayer()
        let repository = FakeAlarmRepository()
        let appLauncher = FakeExternalAppLauncher()

        let missionCoordinator = MissionCoordinator(
            stepCounter: stepCounter,
            qrCodeRepository: FakeQRCodeRepository(),
            puzzleRepository: FakePuzzleRepository(),
            chessEngine: LocalChessEngine()
        )
        let quoteCoordinator = QuoteCoordinator(repository: FakeQuoteRepository(quotes: quotes))
        let wakeUpCoordinator = WakeUpCoordinator(
            scheduler: scheduler,
            missionCoordinator: missionCoordinator,
            stateStore: WakeUpCheckStateStore(fileURL: tempFileURL("wakeup-in-alarm-test-\(UUID().uuidString)"))
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

    func testLastErrorMessageDoesNotOutliveASubsequentSuccess() async {
        // Regression test for a stale "com.apple.AlarmKit.Alarm error 0" banner still showing
        // for an alarm that had since scheduled successfully -- lastErrorMessage was only ever
        // set on failure, never cleared on success, so any one failure anywhere in a session
        // would show forever regardless of what happened afterward.
        let h = makeHarness()
        h.scheduler.authorizationResult = false
        await h.coordinator.refreshAuthorization()
        XCTAssertNotNil(h.coordinator.lastErrorMessage, "sanity check: authorization failure should set an error")

        h.scheduler.authorizationResult = true
        await h.coordinator.refreshAuthorization()
        XCTAssertNil(h.coordinator.lastErrorMessage, "a subsequent successful operation must clear a previous error, not leave it displayed forever")
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
        // The alarm sound deliberately keeps playing through the mission attempt now (stopping
        // it here removed the motivation to actually finish) -- it should only stop once the
        // mission genuinely completes, asserted below.
        XCTAssertEqual(h.audioPlayer.stopCount, 0, "the alarm sound must not stop just because a mission started")

        try await waitForMissionResult(h)

        guard case .snoozed(let until, let snoozedAlarmID) = h.coordinator.runtimeState else {
            XCTFail("expected .snoozed, got \(h.coordinator.runtimeState)")
            return
        }
        XCTAssertEqual(snoozedAlarmID, alarm.id)
        XCTAssertGreaterThan(until, Date())
        XCTAssertEqual(h.audioPlayer.stopCount, 1, "the alarm sound should stop once the mission actually completes")
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
        // Not .last: startMission's fire-and-forget "insurance" re-arm (see
        // AlarmCoordinator) races with the mission completing, so a later
        // scheduledCalls entry isn't guaranteed to be the actual reinstall.
        XCTAssertTrue(
            h.scheduler.scheduledCalls.contains(where: { $0.alarm.id == alarm.id && $0.fireDate == nil }),
            "turning off a repeating alarm should reinstall its native recurring schedule (fireDate: nil) at some point"
        )
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
        // The sound was never stopped when the mission started, so cancelling has nothing to
        // resume -- it should have played exactly once, from the initial ring.
        XCTAssertEqual(h.audioPlayer.playedSounds.count, 1, "cancelling a mission should not need to restart the alarm sound, since it never stopped")
        XCTAssertEqual(h.audioPlayer.stopCount, 0, "cancelling a mission must not stop the alarm sound")
    }

    func testStartingAMissionSchedulesAnInsuranceRearmAgainstForceQuit() async throws {
        // Tapping Turn Off/Snooze on AlarmKit's own system alert appears to silence its native
        // alert immediately, regardless of our custom stopIntent/secondaryIntent (which only
        // opens the app). Without this insurance re-arm, force-quitting the app before actually
        // finishing the mission would leave the alarm silently, permanently dismissed --
        // defeating the entire point of gating dismissal behind a mission.
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .steps(count: 999_999) // never completes on its own
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        let beforeCount = h.scheduler.scheduledCalls.count
        h.coordinator.beginTurnOff()

        // The insurance re-arm is a fire-and-forget Task inside startMission (which is
        // synchronous, matching beginTurnOff()/beginSnooze() being plain SwiftUI button
        // actions, so it can't be awaited directly) -- give it a beat to actually run.
        var found = false
        for _ in 0..<40 {
            if h.scheduler.scheduledCalls.count > beforeCount {
                found = true
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(found, "starting a mission should schedule an insurance re-arm")

        let insuranceCall = try XCTUnwrap(h.scheduler.scheduledCalls.last)
        XCTAssertEqual(insuranceCall.alarm.id, alarm.id)
        let fireDate = try XCTUnwrap(insuranceCall.fireDate)
        XCTAssertEqual(
            fireDate.timeIntervalSinceNow, AlarmCoordinator.missionInsuranceDelay, accuracy: 5,
            "the insurance re-arm should fire well before the mission could ever be abandoned indefinitely"
        )
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

    func testSyncAlertingAlarmsDoesNotResetRingingWhenAlarmKitStopsReportingIt() async throws {
        // Regression test for: tapping Turn Off/Snooze on AlarmKit's own system
        // alert appears to clear its alerting state immediately, independent of
        // our custom stopIntent/secondaryIntent (which only opens the app --
        // see AlarmKitScheduler). The old polling logic treated "AlarmKit no
        // longer reports this as alerting" as "the user dismissed it some other
        // way," resetting .ringing back to .idle within ~1 real second -- often
        // before the user could interact with the in-app mission-gated screen
        // at all. Once ringing, only our own flow should be able to leave it.
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        let alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        await h.coordinator.updateAlarm(alarm)

        h.scheduler.alerting = [alarm.id]
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarm.id))

        // AlarmKit no longer reports it as alerting (e.g. the system alert was
        // tapped) -- our in-app ringing screen must stay up regardless.
        h.scheduler.alerting = []
        await h.coordinator.syncAlertingAlarms()
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarm.id), "polling must not reset .ringing just because AlarmKit's own alerting state changed")
    }

    func testSyncAlertingAlarmsDoesNotResetRunningMissionWhenAlarmKitStopsReportingAlerting() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .steps(count: 999_999) // never completes on its own
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        XCTAssertEqual(h.coordinator.runtimeState, .runningMission(alarmID: alarm.id, action: .turnOff))

        h.scheduler.alerting = []
        await h.coordinator.syncAlertingAlarms()
        XCTAssertEqual(h.coordinator.runtimeState, .runningMission(alarmID: alarm.id, action: .turnOff), "polling must not interrupt an in-progress mission")
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

    // MARK: - Snooze/turn-off with each real mission type
    //
    // The tests above mostly use `.none` for speed/simplicity. These exercise the same
    // beginSnooze()/beginTurnOff() flow with steps, QR, and chess actually configured, since
    // that's where a mismatch between AlarmCoordinator and a specific mission type would show
    // up (e.g. wrong MissionConfiguration case reaching the wrong runner, or a completed/failed
    // interactive session not being picked up correctly). QR and chess are "interactive"
    // missions with no runner — their real completion logic lives in QRMissionContentView's
    // handleDetection(_:) and ChessMissionContentView's handleTap(_:), calling
    // session.complete()/session.fail(reason:) directly (see design.md §28) — not unit-testable
    // without a SwiftUI view-testing setup, so these drive the session the same way those views
    // do, to test everything downstream of that decision instead: AlarmCoordinator's own
    // handling of the mission result.

    func testBeginTurnOffWithStepsMissionCompletesRealistically() async throws {
        // MissionCoordinator.makeSession doesn't expose overriding
        // StepMissionRunner's production defaults (minimumElapsedTime: 8s,
        // maximumStepsPerSecond: 4.0 -- see StepMissionRunner.swift), unlike
        // the standalone runner test in MissionCoordinatorTests.swift which
        // constructs one directly with short test-only values. Going through
        // the real AlarmCoordinator/MissionCoordinator path like a real
        // turn-off would, this test is stuck with those real defaults, so it
        // genuinely takes ~9 real seconds -- that's the price of proving the
        // actual production pipeline (not a shortcut) completes end to end.
        let stepCounter = FakeStepCounter()
        stepCounter.realDelayBetweenUpdatesNanoseconds = 900_000_000 // 900ms/step -> ~1.1 steps/sec, under the 4/sec cap
        let start = Date()
        stepCounter.scriptedUpdates = (0...10).map { i in
            StepUpdate(timestamp: start.addingTimeInterval(Double(i) * 0.9), cumulativeSteps: i)
        }

        let h = makeHarness(stepCounter: stepCounter)
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .steps(count: 10)
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        XCTAssertEqual(h.coordinator.currentMissionSession?.configuration, .steps(count: 10))
        h.coordinator.currentMissionSession?.start()

        // 10 steps * 900ms + minimumElapsedTime's 8s floor means this needs
        // well over waitForMissionResult's 2s budget -- poll directly here
        // instead, up to 15s.
        var resolved = false
        for _ in 0..<600 {
            guard case .runningMission = h.coordinator.runtimeState else {
                resolved = true
                break
            }
            if let result = h.coordinator.currentMissionSession?.result {
                h.coordinator.missionFinished(result)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(resolved, "timed out waiting for the real step mission to resolve")

        guard case .morningComplete = h.coordinator.runtimeState else {
            XCTFail("expected .morningComplete after the steps mission genuinely completes, got \(h.coordinator.runtimeState)")
            return
        }
    }

    func testBeginTurnOffWithQRMissionCompletes() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .qrCode(codeID: nil)
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        XCTAssertEqual(h.coordinator.currentMissionSession?.configuration, .qrCode(codeID: nil))

        // Simulates QRMissionContentView.handleDetection(_:) finding a matching registration.
        h.coordinator.currentMissionSession?.complete()
        try await waitForMissionResult(h)

        guard case .morningComplete = h.coordinator.runtimeState else {
            XCTFail("expected .morningComplete after the QR mission completes, got \(h.coordinator.runtimeState)")
            return
        }
    }

    func testBeginTurnOffWithQRMissionFailureReturnsToRinging() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .qrCode(codeID: nil)
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        // Simulates a scan that couldn't be verified (handleDetection's catch branch) — unlike
        // an unmatched code, which the view just re-prompts on without failing the session, a
        // hard failure is reported through session.fail(reason:).
        h.coordinator.currentMissionSession?.fail(reason: "Couldn't verify that code. Try again.")
        h.coordinator.missionFinished(.failed(reason: "Couldn't verify that code. Try again."))

        XCTAssertEqual(h.coordinator.runtimeState, .ringing(alarmID: alarm.id))
        XCTAssertEqual(h.coordinator.lastErrorMessage, "Couldn't verify that code. Try again.")
    }

    func testBeginTurnOffWithChessMissionCompletes() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.turnOffMission = .chessPuzzle(minRating: 600, maxRating: 900, puzzleCount: 1)
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginTurnOff()
        XCTAssertEqual(h.coordinator.currentMissionSession?.configuration, .chessPuzzle(minRating: 600, maxRating: 900, puzzleCount: 1))

        // Simulates ChessMissionContentView.startPuzzle(at:) calling session.complete() once
        // every puzzle in the set has been solved (solvedMoveCount driven by the real
        // LocalChessEngine, already covered in ChessTests.swift).
        h.coordinator.currentMissionSession?.complete()
        try await waitForMissionResult(h)

        guard case .morningComplete = h.coordinator.runtimeState else {
            XCTFail("expected .morningComplete after the chess mission completes, got \(h.coordinator.runtimeState)")
            return
        }
    }

    func testBeginSnoozeWithChessMissionCompletesAndSchedulesSnooze() async throws {
        let h = makeHarness()
        await h.coordinator.refreshAuthorization()
        var alarm = Alarm(time: LocalTime(hour: 7, minute: 0))
        alarm.snooze = SnoozeConfiguration(
            durationMinutes: 5,
            mission: .chessPuzzle(minRating: 600, maxRating: 900, puzzleCount: 1),
            maxSnoozes: nil
        )
        await h.coordinator.updateAlarm(alarm)
        await h.coordinator.presentRingingAlarm(alarm.id)

        h.coordinator.beginSnooze()
        XCTAssertEqual(h.coordinator.currentMissionSession?.configuration, .chessPuzzle(minRating: 600, maxRating: 900, puzzleCount: 1))

        h.coordinator.currentMissionSession?.complete()
        try await waitForMissionResult(h)

        guard case .snoozed = h.coordinator.runtimeState else {
            XCTFail("expected .snoozed after the chess snooze-mission completes, got \(h.coordinator.runtimeState)")
            return
        }
        XCTAssertNotNil(h.scheduler.scheduledCalls.last?.fireDate, "snoozing must always be a one-shot fireDate override")
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
