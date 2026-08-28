import Foundation

protocol AlarmScheduler: Sendable {
    func requestAuthorizationIfNeeded() async throws -> Bool

    /// Schedules `alarm`. When `fireDate` is `nil`, the scheduler installs the
    /// alarm's own configured time/recurrence (a repeating weekly schedule when
    /// `alarm.recurrence.isRepeating`, otherwise the next one-time occurrence).
    /// When `fireDate` is provided, it installs a one-shot override at that
    /// exact date regardless of recurrence — used for snoozing.
    func schedule(_ alarm: Alarm, fireDate: Date?) async throws
    func cancel(alarmID: UUID) async throws
    func stop(alarmID: UUID) async throws
    func alertingAlarmIDs() async -> [UUID]

    /// Alarms currently in their pre-alert "gentle wake" countdown, i.e.
    /// scheduled with `GentleWakeConfiguration.enabled` and past their
    /// countdown start but not yet at the full alert.
    func countdownAlarmIDs() async -> [UUID]

    /// Debug-only: whatever the underlying scheduler itself currently
    /// believes about this alarm's state (e.g. AlarmKit's raw `Alarm.State`
    /// description), or `nil` if it has no record of this ID at all. Not
    /// meant to be parsed -- purely for surfacing in a diagnostics UI when
    /// something isn't firing as expected and there's no other way to see
    /// what the system alarm daemon actually has scheduled.
    func debugState(for alarmID: UUID) async -> String?
}
