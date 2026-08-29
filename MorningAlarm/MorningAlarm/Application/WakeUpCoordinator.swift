import Foundation
import Observation

/// Runs the second-stage "are you still up?" check entirely independently
/// of the main `AlarmCoordinator` / `AlarmRuntimeState` — it fires later,
/// on its own schedule, and has nothing to do with the primary ringing flow
/// beyond being kicked off once the turn-off mission completes.
@MainActor
@Observable
final class WakeUpCoordinator {
    private(set) var activeAlarmID: UUID?
    private(set) var missionSession: MissionSession?

    private let scheduler: AlarmScheduler
    private let missionCoordinator: MissionCoordinator
    private let stateStore: WakeUpCheckStateStore

    /// checkAlarmID -> original alarm ID. Internal (not private) get so
    /// `@testable import` can assert on it directly.
    private(set) var pendingCheckIDs: [UUID: UUID] = [:]
    private var pollingTask: Task<Void, Never>?

    init(scheduler: AlarmScheduler, missionCoordinator: MissionCoordinator, stateStore: WakeUpCheckStateStore) {
        self.scheduler = scheduler
        self.missionCoordinator = missionCoordinator
        self.stateStore = stateStore
    }

    func start() async {
        pendingCheckIDs = await stateStore.load()
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func schedule(for alarm: Alarm) async {
        guard alarm.wakeUpCheck.enabled else { return }

        let checkID = UUID()
        let fireDate = Date().addingTimeInterval(TimeInterval(alarm.wakeUpCheck.delayMinutes * 60))
        let checkAlarm = Alarm(
            id: checkID,
            time: alarm.time,
            recurrence: .never,
            label: "Wake-up check",
            enabled: true,
            sound: alarm.sound
        )

        pendingCheckIDs[checkID] = alarm.id
        await stateStore.save(pendingCheckIDs)
        try? await scheduler.schedule(checkAlarm, fireDate: fireDate)
    }

    /// Cancels any not-yet-fired check belonging to `alarmID` — call when
    /// the alarm is deleted or disabled.
    func cancelPending(forOriginalAlarmID alarmID: UUID) async {
        let matching = pendingCheckIDs.filter { $0.value == alarmID }
        for checkID in matching.keys {
            pendingCheckIDs[checkID] = nil
            // stop() before cancel(): a check alarm could be actively
            // alerting when this runs, and AlarmCoordinator's own
            // performTurnOff applies the same two-call belt-and-suspenders
            // pattern for exactly that case (see its comment, citing a
            // documented AlarmKit issue where a non-repeating alarm --
            // which every check alarm is -- isn't fully cleared by cancel()
            // alone if it's mid-alert).
            try? await scheduler.stop(alarmID: checkID)
            try? await scheduler.cancel(alarmID: checkID)
        }
        guard !matching.isEmpty else { return }
        await stateStore.save(pendingCheckIDs)
    }

    func beginMission(for alarm: Alarm) {
        guard activeAlarmID != nil else { return }
        missionSession = missionCoordinator.makeSession(for: alarm.wakeUpCheck.mission)
    }

    func missionFinished(_ result: MissionResult) {
        missionSession = nil
        // Completed, cancelled, or failed — either way the check is
        // considered handled. We don't nag with retries.
        activeAlarmID = nil
    }

    func dismiss() {
        missionSession = nil
        activeAlarmID = nil
    }

    /// Internal (not private) so tests can drive one poll cycle directly
    /// instead of waiting on the real 1-second loop.
    func poll() async {
        guard activeAlarmID == nil, !pendingCheckIDs.isEmpty else { return }

        let alertingIDs = await scheduler.alertingAlarmIDs()
        guard let checkID = alertingIDs.first(where: { pendingCheckIDs[$0] != nil }) else { return }
        guard let originalID = pendingCheckIDs[checkID] else { return }

        try? await scheduler.stop(alarmID: checkID)
        // See cancelPending's comment: every check alarm is non-repeating,
        // exactly the case that needs cancel() too, not just stop().
        try? await scheduler.cancel(alarmID: checkID)
        pendingCheckIDs[checkID] = nil
        await stateStore.save(pendingCheckIDs)
        activeAlarmID = originalID
    }
}
