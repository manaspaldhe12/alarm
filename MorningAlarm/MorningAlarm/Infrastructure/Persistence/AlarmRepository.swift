import Foundation

protocol AlarmRepository: Sendable {
    func alarms() async throws -> [Alarm]
    func save(_ alarm: Alarm) async throws
    func delete(id: UUID) async throws
}
