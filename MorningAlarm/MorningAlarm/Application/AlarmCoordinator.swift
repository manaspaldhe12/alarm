import Foundation
import Observation

enum AlarmCoordinatorError: LocalizedError {
    case authorizationDenied
    case alarmNotFound

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Morning Alarm needs permission to schedule alarms. Enable it in Settings."
        case .alarmNotFound:
            return "That alarm could not be found."
        }
    }
}

@MainActor
@Observable
final class AlarmCoordinator {
    private(set) var alarms: [Alarm] = []
    private(set) var runtimeState: AlarmRuntimeState = .idle
    private(set) var authorizationGranted = false
    private(set) var lastErrorMessage: String?
    private(set) var currentMissionSession: MissionSession?
    private(set) var currentQuote: Quote?

    private let repository: AlarmRepository
    private let scheduler: AlarmScheduler
    private let audioPlayer: AlarmAudioPlayer
    private let missionCoordinator: MissionCoordinator
    private let quoteCoordinator: QuoteCoordinator
    let wakeUpCoordinator: WakeUpCoordinator
    let appLauncher: ExternalAppLauncher

    private var observationTask: Task<Void, Never>?
    /// Internal (not private) get so `@testable import` can assert on it.
    private(set) var snoozeCounts: [UUID: Int] = [:]

    init(
        repository: AlarmRepository,
        scheduler: AlarmScheduler,
        audioPlayer: AlarmAudioPlayer,
        missionCoordinator: MissionCoordinator,
        quoteCoordinator: QuoteCoordinator,
        wakeUpCoordinator: WakeUpCoordinator,
        appLauncher: ExternalAppLauncher
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.audioPlayer = audioPlayer
        self.missionCoordinator = missionCoordinator
        self.quoteCoordinator = quoteCoordinator
        self.wakeUpCoordinator = wakeUpCoordinator
        self.appLauncher = appLauncher
    }

    func start() async {
        await refreshAuthorization()
        await reloadAlarms()
        await wakeUpCoordinator.start()
        startObservingSystemAlarms()

        NotificationCenter.default.addObserver(
            forName: .alarmOpenedFromSystem,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let alarmIDString = notification.userInfo?["alarmID"] as? String,
                let alarmID = UUID(uuidString: alarmIDString)
            else { return }

            Task { await self.presentRingingAlarm(alarmID) }
        }
    }

    func refreshAuthorization() async {
        do {
            authorizationGranted = try await scheduler.requestAuthorizationIfNeeded()
            if !authorizationGranted {
                lastErrorMessage = AlarmCoordinatorError.authorizationDenied.errorDescription
            }
        } catch {
            authorizationGranted = false
            lastErrorMessage = error.localizedDescription
        }
    }

    func reloadAlarms() async {
        do {
            alarms = try await repository.alarms().sorted { lhs, rhs in
                if lhs.time.hour == rhs.time.hour {
                    return lhs.time.minute < rhs.time.minute
                }
                return lhs.time.hour < rhs.time.hour
            }
            await reconcileScheduledAlarms()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func createAlarm(at time: LocalTime, label: String = "Alarm") async {
        let alarm = Alarm(time: time, label: label)
        await saveAndSchedule(alarm)
    }

    func updateAlarm(_ alarm: Alarm) async {
        await saveAndSchedule(alarm)
    }

    func deleteAlarm(id: UUID) async {
        do {
            // Best-effort: the alarm may have already fired and been
            // auto-removed by AlarmKit (non-repeating alarms), or never been
            // successfully scheduled in the first place. Either way, that's
            // not a reason to abort deleting it from our own records.
            try? await scheduler.cancel(alarmID: id)
            await wakeUpCoordinator.cancelPending(forOriginalAlarmID: id)
            try await repository.delete(id: id)
            alarms.removeAll { $0.id == id }

            if isCurrentAlarm(id) {
                runtimeState = .idle
                currentMissionSession = nil
                await audioPlayer.stop()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for alarmID: UUID) async {
        guard var alarm = alarms.first(where: { $0.id == alarmID }) else { return }
        alarm.enabled = enabled
        if !enabled {
            await wakeUpCoordinator.cancelPending(forOriginalAlarmID: alarmID)
        }
        await updateAlarm(alarm)
    }

    func alarm(for id: UUID) -> Alarm? {
        alarms.first { $0.id == id }
    }

    /// Debug-only passthrough to the scheduler's raw state for this alarm —
    /// see `AlarmScheduler.debugState(for:)`.
    func debugState(for alarmID: UUID) async -> String? {
        await scheduler.debugState(for: alarmID)
    }

    // MARK: - Ringing flow

    func presentRingingAlarm(_ alarmID: UUID) async {
        guard alarms.contains(where: { $0.id == alarmID }) else { return }
        // Only reset the snooze count on a genuinely fresh cycle (coming from
        // .idle). A post-snooze re-ring arrives from .snoozed — resetting
        // there too would silently defeat maxSnoozes, since every re-ring
        // would zero the count right back out.
        if case .idle = runtimeState {
            snoozeCounts[alarmID] = 0
        }
        runtimeState = .ringing(alarmID: alarmID)

        if let alarm = alarms.first(where: { $0.id == alarmID }) {
            try? audioPlayer.playAlarmSound(alarm.sound)
        }
    }

    func beginSnooze() {
        guard case .ringing(let alarmID) = runtimeState, let alarm = alarms.first(where: { $0.id == alarmID }) else { return }

        if let maxSnoozes = alarm.snooze.maxSnoozes, (snoozeCounts[alarmID] ?? 0) >= maxSnoozes {
            beginTurnOff()
            return
        }

        startMission(alarmID: alarmID, action: .snooze, configuration: alarm.snooze.mission)
    }

    func beginTurnOff() {
        guard case .ringing(let alarmID) = runtimeState, let alarm = alarms.first(where: { $0.id == alarmID }) else { return }
        startMission(alarmID: alarmID, action: .turnOff, configuration: alarm.turnOffMission)
    }

    private func startMission(alarmID: UUID, action: MissionAction, configuration: MissionConfiguration) {
        Task { await audioPlayer.stop() }
        currentMissionSession = missionCoordinator.makeSession(for: configuration)
        runtimeState = .runningMission(alarmID: alarmID, action: action)
    }

    func missionFinished(_ result: MissionResult) {
        guard case .runningMission(let alarmID, let action) = runtimeState else { return }
        currentMissionSession = nil

        switch result {
        case .completed:
            Task {
                switch action {
                case .snooze:
                    await performSnooze(alarmID: alarmID)
                case .turnOff:
                    await performTurnOff(alarmID: alarmID)
                }
            }
        case .failed(let reason):
            lastErrorMessage = reason
            runtimeState = .ringing(alarmID: alarmID)
            if let alarm = alarms.first(where: { $0.id == alarmID }) {
                try? audioPlayer.playAlarmSound(alarm.sound)
            }
        case .cancelled:
            runtimeState = .ringing(alarmID: alarmID)
            if let alarm = alarms.first(where: { $0.id == alarmID }) {
                try? audioPlayer.playAlarmSound(alarm.sound)
            }
        }
    }

    func acknowledgeSnoozeConfirmation() {
        guard case .snoozed = runtimeState else { return }
        currentQuote = nil
    }

    func finishMorningComplete() {
        guard case .morningComplete = runtimeState else { return }
        runtimeState = .idle
        currentQuote = nil
    }

    private func performSnooze(alarmID: UUID) async {
        guard let alarm = alarms.first(where: { $0.id == alarmID }) else { return }

        do {
            snoozeCounts[alarmID, default: 0] += 1
            let snoozeUntil = Date().addingTimeInterval(alarm.snooze.duration)
            try await scheduler.schedule(alarm, fireDate: snoozeUntil)
            currentQuote = await quoteCoordinator.quote(for: .snoozed)
            runtimeState = .snoozed(until: snoozeUntil, alarmID: alarmID)
        } catch {
            lastErrorMessage = error.localizedDescription
            runtimeState = .ringing(alarmID: alarmID)
        }
    }

    private func performTurnOff(alarmID: UUID) async {
        do {
            try await scheduler.stop(alarmID: alarmID)

            guard var alarm = alarms.first(where: { $0.id == alarmID }) else {
                runtimeState = .idle
                return
            }

            if alarm.enabled {
                if alarm.recurrence.isRepeating {
                    try await scheduler.schedule(alarm, fireDate: nil)
                } else {
                    alarm.enabled = false
                    try await repository.save(alarm)
                    if let index = alarms.firstIndex(where: { $0.id == alarmID }) {
                        alarms[index] = alarm
                    }
                }
            }

            await wakeUpCoordinator.cancelPending(forOriginalAlarmID: alarmID)
            await wakeUpCoordinator.schedule(for: alarm)

            currentQuote = await quoteCoordinator.quote(for: .alarmCompleted)
            runtimeState = .morningComplete(alarmID: alarmID)
        } catch {
            lastErrorMessage = error.localizedDescription
            runtimeState = .idle
        }
    }

    // MARK: - Persistence + scheduling

    private func saveAndSchedule(_ alarm: Alarm) async {
        do {
            try await repository.save(alarm)

            if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[index] = alarm
            } else {
                alarms.append(alarm)
            }

            alarms.sort { lhs, rhs in
                if lhs.time.hour == rhs.time.hour {
                    return lhs.time.minute < rhs.time.minute
                }
                return lhs.time.hour < rhs.time.hour
            }

            // Best-effort cleanup of any prior schedule for this ID (there
            // usually isn't one for a brand-new alarm) -- must never block
            // the actual schedule() call below, since that's the one that
            // matters.
            try? await scheduler.cancel(alarmID: alarm.id)

            if alarm.enabled {
                guard authorizationGranted else {
                    throw AlarmCoordinatorError.authorizationDenied
                }
                try await scheduler.schedule(alarm, fireDate: nil)
            } else {
                await wakeUpCoordinator.cancelPending(forOriginalAlarmID: alarm.id)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func reconcileScheduledAlarms() async {
        guard authorizationGranted else { return }

        for alarm in alarms where alarm.enabled {
            do {
                try await scheduler.schedule(alarm, fireDate: nil)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func startObservingSystemAlarms() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncAlertingAlarms()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func isCurrentAlarm(_ id: UUID) -> Bool {
        switch runtimeState {
        case .idle:
            return false
        case .gentleWake(let alarmID), .ringing(let alarmID), .snoozed(_, let alarmID), .morningComplete(let alarmID):
            return alarmID == id
        case .runningMission(let alarmID, _):
            return alarmID == id
        }
    }

    /// Internal (not private) so tests can drive one sync cycle directly
    /// instead of waiting on the real 1-second loop.
    func syncAlertingAlarms() async {
        let knownAlarmIDs = Set(alarms.map(\.id))

        let alertingIDs = await scheduler.alertingAlarmIDs()
        if let alertingID = alertingIDs.first(where: { knownAlarmIDs.contains($0) }) {
            if case .ringing(let currentID) = runtimeState, currentID == alertingID {
                return
            }
            if case .runningMission(let currentID, _) = runtimeState, currentID == alertingID {
                return
            }
            await presentRingingAlarm(alertingID)
            return
        }

        let countdownIDs = await scheduler.countdownAlarmIDs()
        if let countdownID = countdownIDs.first(where: { knownAlarmIDs.contains($0) }) {
            if case .gentleWake(let currentID) = runtimeState, currentID == countdownID {
                return
            }
            if case .idle = runtimeState, let alarm = alarms.first(where: { $0.id == countdownID }) {
                runtimeState = .gentleWake(alarmID: countdownID)
                try? audioPlayer.playGentleWake(alarm.sound, rampDuration: alarm.gentleWake.duration)
            }
            return
        }

        if case .gentleWake = runtimeState {
            runtimeState = .idle
            await audioPlayer.stop()
        }

        if case .ringing = runtimeState {
            runtimeState = .idle
            await audioPlayer.stop()
        }

        if case .snoozed(let until, let alarmID) = runtimeState, Date() >= until {
            await presentRingingAlarm(alarmID)
        }
    }
}
