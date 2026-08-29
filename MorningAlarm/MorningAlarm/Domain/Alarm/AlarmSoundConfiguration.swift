import Foundation

enum AlarmSoundConfiguration: Codable, Equatable {
    /// iOS's own built-in alarm tone, played by AlarmKit itself. Tried as
    /// the default first, but in practice it's a harsh, siren-like tone —
    /// not the gentler Clock-app-style sound it was expected to be, and we
    /// have no way to pick a *specific* nicer system tone by name through
    /// AlarmKit's public API. Left available in case a future setting wants
    /// to offer it as an option, but no longer the default.
    case systemDefault
    /// A custom sound file bundled in the app (base name, no extension --
    /// callers append their own, since `Bundle.url(forResource:withExtension:)`
    /// and AlarmKit's `AlertConfiguration.AlertSound.named(_:)` want it
    /// split vs. combined respectively).
    case bundled(fileName: String)

    /// A gentle four-note ascending chime (bundled `default_alarm.wav`)
    /// instead of `.systemDefault` -- see that case's doc comment for why.
    static let `default`: AlarmSoundConfiguration = .bundled(fileName: "default_alarm")
}
