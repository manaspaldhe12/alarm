import Foundation

enum AlarmRuntimeState: Equatable {
    case idle
    case ringing(alarmID: UUID)
    case snoozed(until: Date, alarmID: UUID)
}
