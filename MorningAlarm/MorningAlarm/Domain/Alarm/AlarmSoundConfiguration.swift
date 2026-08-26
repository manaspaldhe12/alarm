import Foundation

struct AlarmSoundConfiguration: Codable, Equatable {
    var fileName: String

    static let `default` = AlarmSoundConfiguration(fileName: "default_alarm")

    /// AlarmKit's `AlertConfiguration.AlertSound.named(_:)` wants the full
    /// filename *including* its extension (every documented example uses
    /// something like "Glass Drum.caf") — unlike
    /// `Bundle.url(forResource:withExtension:)`, which wants them split,
    /// and is why `fileName` itself is stored without one.
    var fileNameWithExtension: String { "\(fileName).wav" }
}
