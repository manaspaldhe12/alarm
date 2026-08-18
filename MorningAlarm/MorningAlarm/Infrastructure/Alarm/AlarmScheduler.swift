import Foundation

protocol AlarmScheduler: Sendable {
    func requestAuthorizationIfNeeded() async throws -> Bool
    func schedule(_ alarm: Alarm, fireDate: Date) async throws
    func cancel(alarmID: UUID) async throws
    func stop(alarmID: UUID) async throws
    func alertingAlarmIDs() async -> [UUID]
}
