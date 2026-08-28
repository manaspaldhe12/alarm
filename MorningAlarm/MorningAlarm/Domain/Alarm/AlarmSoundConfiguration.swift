import Foundation

enum AlarmSoundConfiguration: Codable, Equatable {
    /// iOS's own built-in alarm tone, played by AlarmKit itself — the same
    /// sound the system Clock app uses. The default: more melodious than a
    /// bundled placeholder, and needs no bundled asset at all.
    case systemDefault
    /// A custom sound file bundled in the app (base name, no extension --
    /// callers append their own, since `Bundle.url(forResource:withExtension:)`
    /// and AlarmKit's `AlertConfiguration.AlertSound.named(_:)` want it
    /// split vs. combined respectively).
    case bundled(fileName: String)

    static let `default`: AlarmSoundConfiguration = .systemDefault
}
