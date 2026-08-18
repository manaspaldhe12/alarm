import Foundation

struct SnoozeConfiguration: Codable, Equatable {
    var durationMinutes: Int

    static let `default` = SnoozeConfiguration(durationMinutes: 10)

    var duration: TimeInterval {
        TimeInterval(durationMinutes * 60)
    }
}
