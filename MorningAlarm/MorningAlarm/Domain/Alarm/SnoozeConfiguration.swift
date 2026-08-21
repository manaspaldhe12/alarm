import Foundation

struct SnoozeConfiguration: Codable, Equatable {
    var durationMinutes: Int
    var mission: MissionConfiguration
    /// `nil` means unlimited snoozes.
    var maxSnoozes: Int?

    init(durationMinutes: Int, mission: MissionConfiguration = .defaultSnooze, maxSnoozes: Int? = nil) {
        self.durationMinutes = durationMinutes
        self.mission = mission
        self.maxSnoozes = maxSnoozes
    }

    static let `default` = SnoozeConfiguration(durationMinutes: 10)

    var duration: TimeInterval {
        TimeInterval(durationMinutes * 60)
    }
}
