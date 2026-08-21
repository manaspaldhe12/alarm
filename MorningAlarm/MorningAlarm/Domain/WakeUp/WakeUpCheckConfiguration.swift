import Foundation

struct WakeUpCheckConfiguration: Codable, Equatable {
    var enabled: Bool
    var delayMinutes: Int
    var mission: MissionConfiguration

    static let `default` = WakeUpCheckConfiguration(enabled: false, delayMinutes: 15, mission: .defaultWakeUpCheck)
}
