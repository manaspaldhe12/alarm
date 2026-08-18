import Foundation

struct AlarmSoundConfiguration: Codable, Equatable {
    var fileName: String

    static let `default` = AlarmSoundConfiguration(fileName: "default_alarm")
}
