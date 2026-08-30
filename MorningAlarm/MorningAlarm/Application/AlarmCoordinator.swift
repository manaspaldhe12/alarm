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
    let insuranceDiagnostics: InsuranceDiagnosticsLog
    /// Internal (not private) so tests can assert on it directly.
    let missionInsuranceState: MissionInsuranceStateStore

    private var observationTask: Task<Void, Never>?
    /// Internal (not private) get so `@testable import` can assert on it.
    private(set) var snoozeCounts: [UUID: Int] = [:]
    /// The in-flight "insurance" re-arm Task from `startMission`, if any —
    /// see that method and `performSnooze`/`performTurnOff` for why this
    /// must be awaited (not just fired-and-forgotten) before either of
    /// those does its own real scheduling.
    private var insuranceTask: Task<Void, Never>?
    /// Reentrancy guard for `missionFinished(.completed)`: the runtimeState
    /// guard there only actually changes once the spawned Task runs, so a
    /// duplicate call arriving before that would otherwise pass the same
    /// guard twice and spawn two concurrent performSnooze/performTurnOff
    /// calls for the same alarm.
    private var isFinishingMission = false

    init(
        repository: AlarmRepository,
        scheduler: AlarmScheduler,
        audioPlayer: AlarmAudioPlayer,
        missionCoordinator: MissionCoordinator,
        quoteCoordinator: QuoteCoordinator,
        wakeUpCoordinator: WakeUpCoordinator,
        appLauncher: ExternalAppLauncher,
        insuranceDiagnostics: InsuranceDiagnosticsLog = InsuranceDiagnosticsLog(),
        missionInsuranceState: MissionInsuranceStateStore = MissionInsuranceStateStore()
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.audioPlayer = audioPlayer
        self.missionCoordinator = missionCoordinator
        self.quoteCoordinator = quoteCoordinator
        self.wakeUpCoordinator = wakeUpCoordinator
        self.appLauncher = appLauncher
        self.insuranceDiagnostics = insuranceDiagnostics
        self.missionInsuranceState = missionInsuranceState
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
        lastErrorMessage = nil
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
        lastErrorMessage = nil
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
        lastErrorMessage = nil
        if isCurrentAlarm(id) {
            insuranceTask?.cancel()
            insuranceTask = nil
            await retireOutstandingShadows(for: id)
        }

        // Best-effort: the alarm may have already fired and been
        // auto-removed by AlarmKit (non-repeating alarms), or never been
        // successfully scheduled in the first place. Either way, that's
        // not a reason to abort deleting it from our own records.
        try? await scheduler.cancel(alarmID: id)
        await wakeUpCoordinator.cancelPending(forOriginalAlarmID: id)

        do {
            try await repository.delete(id: id)
        } catch {
            // The AlarmKit registration is already gone regardless (best-
            // effort above) -- still remove it from our own list below
            // rather than leaving a "ghost" the user thinks is still
            // active but which will never actually fire again. The error
            // is still surfaced so something visibly went wrong.
            lastErrorMessage = error.localizedDescription
        }

        alarms.removeAll { $0.id == id }

        if isCurrentAlarm(id) {
            runtimeState = .idle
            currentMissionSession = nil
            await audioPlayer.stop()
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
        guard let alarm = alarms.first(where: { $0.id == alarmID }) else { return }
        // Only reset the snooze count on a genuinely fresh cycle (coming from
        // .idle). A post-snooze re-ring arrives from .snoozed — resetting
        // there too would silently defeat maxSnoozes, since every re-ring
        // would zero the count right back out.
        if case .idle = runtimeState {
            snoozeCounts[alarmID] = 0
        }
        runtimeState = .ringing(alarmID: alarmID)
        try? audioPlayer.playAlarmSound(alarm.sound)

        // If this alarm had a mission genuinely in progress the last time we
        // knew about it (persisted by startMission, cleared on completion —
        // see MissionInsuranceStateStore), this ring is very likely
        // AlarmKit's own insurance re-arm firing again after the app was
        // force-quit mid-mission, not a fresh alarm. Jump straight back into
        // that same mission (restarting its insurance coverage) instead of
        // leaving the user at a bare .ringing screen that needs a button tap
        // before any protection resumes -- without this, a *second*
        // force-quit (before that tap) would have nothing left to re-arm it
        // a second time.
        if let inProgress = await missionInsuranceState.load(), inProgress.alarmID == alarmID {
            let configuration = inProgress.action == .snooze ? alarm.snooze.mission : alarm.turnOffMission
            startMission(alarmID: alarmID, action: inProgress.action, configuration: configuration)
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

    /// How many independent "shadow" AlarmKit registrations each insurance
    /// burst (see `startMission`) pre-commits at once, and how far apart
    /// their fire dates are staggered.
    ///
    /// Modeled on how other iOS alarm apps survive a force-quit: rather
    /// than depending on a live process to keep re-arming a *single* alarm
    /// ID just-in-time (which fails outright if the process dies before the
    /// next re-arm call completes -- confirmed on-device: swiping away from
    /// a bare, untouched ringing screen was already enough to lose the
    /// alert entirely), pre-commit several *independent* registrations up
    /// front. Apple's own AlarmKit FAQ says a successfully-scheduled alarm
    /// "is expected to persist regardless of app or device state changes"
    /// (developer.apple.com/forums/thread/797158) -- each shadow, once its
    /// own schedule() call returns, is durable at the system level
    /// regardless of this app's process, so a force-quit immediately after
    /// the whole burst completes still leaves every one of them intact, not
    /// just whichever single one happened to be scheduled most recently.
    static let insuranceShadowCount = 6
    static let insuranceShadowSpacing: TimeInterval = 12

    /// The alarm sound deliberately keeps playing through the whole mission
    /// attempt — silencing it here (as this used to do) removed the
    /// motivation to actually finish quickly, which defeats the point of
    /// gating dismissal behind a mission at all. It's only stopped once a
    /// mission genuinely completes (see `performSnooze`/`performTurnOff`);
    /// failing or cancelling a mission leaves it playing uninterrupted,
    /// since it was never stopped to begin with.
    private func startMission(alarmID: UUID, action: MissionAction, configuration: MissionConfiguration) {
        // A retry (failed/cancelled mission -> back to .ringing -> tapped
        // again) calls this a second time -- cancel any still-outstanding
        // insurance Task from the previous attempt first, since it's
        // superseded by the new one below.
        insuranceTask?.cancel()

        currentMissionSession = missionCoordinator.makeSession(for: configuration)
        runtimeState = .runningMission(alarmID: alarmID, action: action)

        // Insurance against the app dying mid-mission (force-quit from the
        // app switcher, a crash, iOS reclaiming memory, etc.): tapping
        // Turn Off/Snooze on AlarmKit's own system alert appears to silence
        // its native alert immediately, regardless of our custom
        // stopIntent/secondaryIntent -- which only opens the app and never
        // itself calls stop(). That's exactly right when the mission then
        // actually gets completed, but if the app dies before that, the
        // alarm would otherwise just stay silently dismissed with nothing
        // ever having been asked of the user -- defeating the entire point
        // of gating dismissal behind a mission.
        guard let alarm = alarms.first(where: { $0.id == alarmID }) else { return }

        let diagnostics = insuranceDiagnostics
        let missionState = missionInsuranceState
        let scheduler = self.scheduler
        insuranceTask = Task {
            // Retire any stale shadow batch from a previous attempt for this
            // same alarm (a retry within this process, or a resume after a
            // relaunch that found a batch this process never got to clean
            // up) before committing a fresh one below.
            if let stale = await missionState.load(), stale.alarmID == alarmID {
                for shadowID in stale.shadowIDs {
                    try? await scheduler.stop(alarmID: shadowID)
                    try? await scheduler.cancel(alarmID: shadowID)
                }
            }

            while !Task.isCancelled {
                let shadowIDs = (0..<Self.insuranceShadowCount).map { _ in UUID() }
                // Persisted before the burst even fires, so a relaunch knows
                // both that this mission was in progress and exactly which
                // shadow IDs to clean up later, even if the process dies
                // mid-burst -- see MissionInsuranceStateStore and
                // presentRingingAlarm.
                await missionState.save(.init(alarmID: alarmID, action: action, shadowIDs: shadowIDs))

                await withTaskGroup(of: Void.self) { group in
                    for (index, shadowID) in shadowIDs.enumerated() {
                        group.addTask {
                            let fireDate = Date().addingTimeInterval(Self.insuranceShadowSpacing * Double(index + 1))
                            do {
                                try await scheduler.scheduleShadowInsurance(shadowID: shadowID, for: alarm, fireDate: fireDate)
                                await diagnostics.record(targetFireDate: fireDate, outcome: "scheduled")
                            } catch {
                                // Deliberately NOT swallowed via `try?` here
                                // (unlike most other best-effort scheduler
                                // calls in this file) -- this burst is the
                                // only thing standing between a force-quit
                                // mid-mission and the alarm staying
                                // silently, permanently dismissed, so a
                                // failure here needs to be visible on the
                                // next launch (see InsuranceDiagnosticsLog),
                                // not silently discarded.
                                await diagnostics.record(targetFireDate: fireDate, outcome: "failed: \(error.localizedDescription)")
                            }
                        }
                    }
                }

                // While the process stays alive, refresh with a fresh batch
                // partway through this one's coverage window -- a
                // long-running mission (e.g. genuinely walking 50 steps)
                // shouldn't be able to outlast the window and go uncovered.
                let refreshDelay = Self.insuranceShadowSpacing * Double(Self.insuranceShadowCount) / 2
                try? await Task.sleep(for: .seconds(refreshDelay))
                guard !Task.isCancelled else { break }
                // A legitimate in-progress mission should never let two
                // batches' alerts collide -- retire this batch just before
                // the next loop iteration commits its replacement.
                for shadowID in shadowIDs {
                    try? await scheduler.stop(alarmID: shadowID)
                    try? await scheduler.cancel(alarmID: shadowID)
                }
            }
        }
    }

    /// Cancels every outstanding insurance shadow registration for
    /// `alarmID` (if any are currently persisted) and clears the in-progress
    /// flag -- called once a mission is genuinely, definitively done (or the
    /// alarm it belonged to is deleted), so none of them fire spuriously
    /// after the fact. Safe to call even with nothing outstanding.
    private func retireOutstandingShadows(for alarmID: UUID) async {
        if let inProgress = await missionInsuranceState.load(), inProgress.alarmID == alarmID {
            for shadowID in inProgress.shadowIDs {
                try? await scheduler.stop(alarmID: shadowID)
                try? await scheduler.cancel(alarmID: shadowID)
            }
        }
        await missionInsuranceState.save(nil)
    }

    func missionFinished(_ result: MissionResult) {
        guard case .runningMission(let alarmID, let action) = runtimeState, !isFinishingMission else { return }
        currentMissionSession = nil

        switch result {
        case .completed:
            isFinishingMission = true
            Task {
                switch action {
                case .snooze:
                    await performSnooze(alarmID: alarmID)
                case .turnOff:
                    await performTurnOff(alarmID: alarmID)
                }
                isFinishingMission = false
            }
        case .failed(let reason):
            lastErrorMessage = reason
            runtimeState = .ringing(alarmID: alarmID)
        case .cancelled:
            runtimeState = .ringing(alarmID: alarmID)
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

        lastErrorMessage = nil
        // Stop (it's a loop now, not a one-shot -- it never finishes on its
        // own) and wait for startMission's insurance re-arm before our own
        // real scheduling below -- otherwise the two race and a heartbeat
        // iteration can land after this one and silently overwrite the
        // snooze duration the user actually chose.
        insuranceTask?.cancel()
        await insuranceTask?.value
        insuranceTask = nil
        do {
            snoozeCounts[alarmID, default: 0] += 1
            // Explicitly stop the currently-alerting native alarm before
            // rescheduling -- otherwise it's not confirmed whether
            // installing a new fireDate on an already-alerting alarm alone
            // reliably silences it.
            try? await scheduler.stop(alarmID: alarmID)
            let snoozeUntil = Date().addingTimeInterval(alarm.snooze.duration)
            try await scheduler.schedule(alarm, fireDate: snoozeUntil)
            await audioPlayer.stop()
            // Only on this definitively-successful path -- a thrown error
            // below (caught below) means the mission itself was completed
            // but scheduling the snooze wasn't, so the user is dumped back
            // to .ringing and still genuinely needs insurance coverage
            // (including its outstanding shadow registrations, left alone
            // below in that case).
            await retireOutstandingShadows(for: alarmID)
            currentQuote = await quoteCoordinator.quote(for: .snoozed)
            runtimeState = .snoozed(until: snoozeUntil, alarmID: alarmID)
        } catch {
            lastErrorMessage = error.localizedDescription
            runtimeState = .ringing(alarmID: alarmID)
        }
    }

    private func performTurnOff(alarmID: UUID) async {
        lastErrorMessage = nil
        // See performSnooze -- must happen before this method's own real
        // scheduling/cancelling below, for the same race-avoidance reason.
        insuranceTask?.cancel()
        await insuranceTask?.value
        insuranceTask = nil
        do {
            // Both best-effort: the actual outcome we need -- disabled/
            // reinstalled, sound stopped, user sees morning-complete --
            // must not be blocked by AlarmKit's own stop()/cancel() failing,
            // especially given each is a fallback for the other already.
            try? await scheduler.stop(alarmID: alarmID)
            // Belt-and-suspenders: there's a documented AlarmKit issue where
            // a non-repeating alarm isn't fully cleared out after firing
            // (https://developer.apple.com/forums/thread/796901), and stop()
            // alone wasn't confirmed to reliably silence things either (see
            // the insurance re-arm in startMission -- this cancel() also
            // wipes that out, since a completed mission is exactly the case
            // it must not fire for). Best-effort: must never block finishing
            // the turn-off that matters.
            try? await scheduler.cancel(alarmID: alarmID)
            await audioPlayer.stop()

            guard var alarm = alarms.first(where: { $0.id == alarmID }) else {
                await retireOutstandingShadows(for: alarmID)
                runtimeState = .idle
                return
            }

            if alarm.enabled {
                if alarm.recurrence.isRepeating {
                    // cancel() above wiped the native recurring schedule too -- reinstall it.
                    do {
                        try await scheduler.schedule(alarm, fireDate: nil)
                    } catch {
                        // Reinstalling failed -- rather than silently leaving
                        // the alarm "enabled" in the UI/repository with
                        // nothing actually scheduled (which would never fire
                        // again until the user happened to notice and
                        // re-toggle it), disable it so the UI honestly
                        // reflects that it needs attention. The rest of
                        // turn-off (wake-up check, morning-complete) still
                        // proceeds -- the user did finish their mission.
                        lastErrorMessage = error.localizedDescription
                        alarm.enabled = false
                        try? await repository.save(alarm)
                        if let index = alarms.firstIndex(where: { $0.id == alarmID }) {
                            alarms[index] = alarm
                        }
                    }
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

            // Definitively-successful path only -- see performSnooze's same call.
            await retireOutstandingShadows(for: alarmID)
            currentQuote = await quoteCoordinator.quote(for: .alarmCompleted)
            runtimeState = .morningComplete(alarmID: alarmID)
        } catch {
            lastErrorMessage = error.localizedDescription
            runtimeState = .idle
        }
    }

    // MARK: - Persistence + scheduling

    private func saveAndSchedule(_ alarm: Alarm) async {
        var alarm = alarm
        lastErrorMessage = nil
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
            // The save + array update above already happened, so the alarm
            // may be persisted/listed as enabled even though scheduling
            // failed -- roll that back rather than leaving the UI lying
            // about being scheduled when AlarmKit has nothing for it.
            if alarm.enabled {
                alarm.enabled = false
                try? await repository.save(alarm)
                if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                    alarms[index] = alarm
                }
            }
        }
    }

    /// How far in the past an enabled alarm's regular fire time can be and
    /// still count as "possibly missed" by `reconcileScheduledAlarms`,
    /// rather than a normal future occurrence.
    static let missedAlarmGracePeriod: TimeInterval = 20 * 60

    private func reconcileScheduledAlarms() async {
        guard authorizationGranted else { return }

        for alarm in alarms where alarm.enabled {
            // Skip alarms AlarmKit already has *some* record of (its
            // regular schedule, an active one-shot snooze override,
            // mid-alert, etc.). This runs on every launch/reload;
            // rescheduling unconditionally here would silently clobber e.g.
            // a still-pending snooze fireDate with the alarm's regular
            // (possibly much later) schedule the moment the app relaunches
            // during a snooze window.
            guard await scheduler.debugState(for: alarm.id) == nil else { continue }

            // AlarmKit has *no* record of this alarm at all -- normally
            // because it's simply never been scheduled yet. But that's also
            // exactly what it looks like when the alarm was actively
            // alerting and the app got force-quit before it was
            // acknowledged: on-device testing showed AlarmKit's own record
            // of an in-flight alert does not reliably survive that (contrary
            // to what Apple's AlarmKit FAQ implies -- see the README).
            // Unconditionally rescheduling straight for the alarm's *next*
            // regular occurrence in that case means the user reopens the
            // app, sees nothing wrong, and an alarm they never actually
            // dealt with just quietly waits until tomorrow with no alert
            // ever shown. Recompute whether *this* alarm's regular time
            // already passed recently (within missedAlarmGracePeriod)
            // rather than having rolled over to a later one -- if so, show
            // the ringing screen (and let mission-gating apply normally)
            // instead of silently scheduling past it unacknowledged.
            let recentFireDate = alarm.nextFireDate(from: Date().addingTimeInterval(-Self.missedAlarmGracePeriod))
            if recentFireDate <= Date() {
                // `return`, not `continue`: presentRingingAlarm overwrites
                // runtimeState, so if some other enabled alarm in this same
                // loop also qualified, a second call here would silently
                // stomp this one's ringing presentation. Any other alarm
                // still needing a plain reschedule this pass will get one
                // on the next reload instead -- a rare, low-cost tradeoff
                // against two "missed" alarms colliding.
                await presentRingingAlarm(alarm.id)
                return
            }

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
    ///
    /// Polling only ever detects NEW transitions *into* a ringing/mission
    /// flow (from `.idle` or `.gentleWake`) — it must never transition back
    /// *out* of `.ringing`/`.runningMission` on its own. This used to reset
    /// `.ringing` to `.idle` the moment `scheduler.alertingAlarmIDs()`
    /// stopped reporting the alarm, on the assumption that meant the alarm
    /// was genuinely dismissed. In practice, tapping Turn Off/Snooze on
    /// AlarmKit's own system alert appears to clear its *own* alerting
    /// state immediately, independent of whatever our custom
    /// stopIntent/secondaryIntent's perform() actually does (which, by
    /// design, is just "open the app" — it never calls stop()/schedule()
    /// itself). With the old code, the very next 1-second poll would see
    /// "not alerting anymore" and silently reset .ringing to .idle before
    /// the user had any real chance to interact with the mission-gated
    /// in-app screen — the exact "opens, rings once, and stops, no mission
    /// enforced" behavior that was reported. Once the user is in
    /// `.ringing`/`.runningMission`, only their own actions (or a mission
    /// actually finishing) should move things forward now.
    func syncAlertingAlarms() async {
        let knownAlarmIDs = Set(alarms.map(\.id))

        switch runtimeState {
        case .idle:
            let alertingIDs = await scheduler.alertingAlarmIDs()
            if let alertingID = alertingIDs.first(where: { knownAlarmIDs.contains($0) }) {
                await presentRingingAlarm(alertingID)
                return
            }

            let countdownIDs = await scheduler.countdownAlarmIDs()
            if let countdownID = countdownIDs.first(where: { knownAlarmIDs.contains($0) }),
               let alarm = alarms.first(where: { $0.id == countdownID }) {
                runtimeState = .gentleWake(alarmID: countdownID)
                try? audioPlayer.playGentleWake(alarm.sound, rampDuration: alarm.gentleWake.duration)
            }

        case .gentleWake(let countdownID):
            let alertingIDs = await scheduler.alertingAlarmIDs()
            if alertingIDs.contains(countdownID) {
                await presentRingingAlarm(countdownID)
                return
            }

            let countdownIDs = await scheduler.countdownAlarmIDs()
            if !countdownIDs.contains(countdownID) {
                // The countdown ended without reaching a real alert (e.g. the
                // alarm was cancelled mid-ramp) — stop the gentle-wake audio.
                runtimeState = .idle
                await audioPlayer.stop()
            }

        case .snoozed(let until, let alarmID):
            if Date() >= until {
                await presentRingingAlarm(alarmID)
            }

        case .ringing, .runningMission, .morningComplete:
            break
        }
    }
}
