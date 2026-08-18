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

    private let repository: AlarmRepository
    private let scheduler: AlarmScheduler
    private let audioPlayer: AlarmAudioPlayer
    private var observationTask: Task<Void, Never>?

    init(
        repository: AlarmRepository,
        scheduler: AlarmScheduler,
        audioPlayer: AlarmAudioPlayer
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.audioPlayer = audioPlayer
    }

    func start() async {
        await refreshAuthorization()
        await reloadAlarms()
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
            try await scheduler.cancel(alarmID: id)
            try await repository.delete(id: id)
            alarms.removeAll { $0.id == id }

            if case .ringing(let ringingID) = runtimeState, ringingID == id {
                runtimeState = .idle
                await audioPlayer.stop()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for alarmID: UUID) async {
        guard var alarm = alarms.first(where: { $0.id == alarmID }) else { return }
        alarm.enabled = enabled
        await updateAlarm(alarm)
    }

    func turnOffCurrentAlarm() async {
        guard case .ringing(let alarmID) = runtimeState else { return }

        do {
            try await scheduler.stop(alarmID: alarmID)
            await audioPlayer.stop()
            runtimeState = .idle

            if let alarm = alarms.first(where: { $0.id == alarmID }), alarm.enabled {
                try await scheduler.schedule(alarm, fireDate: alarm.time.nextFireDate())
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func snoozeCurrentAlarm() async {
        guard
            case .ringing(let alarmID) = runtimeState,
            let alarm = alarms.first(where: { $0.id == alarmID })
        else { return }

        do {
            try await scheduler.stop(alarmID: alarmID)
            await audioPlayer.stop()

            let snoozeUntil = Date().addingTimeInterval(alarm.snooze.duration)
            runtimeState = .snoozed(until: snoozeUntil, alarmID: alarmID)
            try await scheduler.schedule(alarm, fireDate: snoozeUntil)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func presentRingingAlarm(_ alarmID: UUID) async {
        guard alarms.contains(where: { $0.id == alarmID }) else { return }
        runtimeState = .ringing(alarmID: alarmID)

        if let alarm = alarms.first(where: { $0.id == alarmID }) {
            try? audioPlayer.playAlarmSound(alarm.sound)
        }
    }

    func alarm(for id: UUID) -> Alarm? {
        alarms.first { $0.id == id }
    }

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

            try await scheduler.cancel(alarmID: alarm.id)

            if alarm.enabled {
                guard authorizationGranted else {
                    throw AlarmCoordinatorError.authorizationDenied
                }
                try await scheduler.schedule(alarm, fireDate: alarm.time.nextFireDate())
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func reconcileScheduledAlarms() async {
        guard authorizationGranted else { return }

        for alarm in alarms where alarm.enabled {
            do {
                try await scheduler.schedule(alarm, fireDate: alarm.time.nextFireDate())
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

    private func syncAlertingAlarms() async {
        let alertingIDs = await scheduler.alertingAlarmIDs()

        if let first = alertingIDs.first {
            if case .ringing(let currentID) = runtimeState, currentID == first {
                return
            }
            await presentRingingAlarm(first)
            return
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
