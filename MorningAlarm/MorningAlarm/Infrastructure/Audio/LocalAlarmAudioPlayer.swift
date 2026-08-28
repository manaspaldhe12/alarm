import AVFoundation
import Foundation

protocol AlarmAudioPlayer: Sendable {
    func playAlarmSound(_ sound: AlarmSoundConfiguration) throws
    /// Loops `sound` starting near-silent and ramping to full volume over
    /// `rampDuration` — used for the gentle-wake pre-alert period. Best
    /// effort only: reliably audible while the app is foregrounded; the
    /// full-volume alert at the real alarm time is what's guaranteed.
    func playGentleWake(_ sound: AlarmSoundConfiguration, rampDuration: TimeInterval) throws
    func stop() async
}

final class LocalAlarmAudioPlayer: AlarmAudioPlayer, @unchecked Sendable {
    /// We have no way to play iOS's actual built-in alarm tone ourselves
    /// outside of AlarmKit's own alert mechanism (`.systemDefault` there
    /// maps to `AlertConfiguration.AlertSound.default`) -- this bundled
    /// file is the closest local approximation for our own AVAudioPlayer-
    /// driven playback (the custom ringing screen, the gentle-wake ramp).
    private static let fallbackFileName = "default_alarm"

    private var player: AVAudioPlayer?

    func playAlarmSound(_ sound: AlarmSoundConfiguration) throws {
        stopSync()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        let fileName = Self.localPlaybackFileName(for: sound)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
            throw AlarmAudioError.soundNotFound(fileName)
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
        self.player = player
    }

    func playGentleWake(_ sound: AlarmSoundConfiguration, rampDuration: TimeInterval) throws {
        stopSync()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        let fileName = Self.localPlaybackFileName(for: sound)
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
            throw AlarmAudioError.soundNotFound(fileName)
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        player.volume = 0.05
        player.prepareToPlay()
        player.play()
        player.setVolume(1.0, fadeDuration: rampDuration)
        self.player = player
    }

    func stop() async {
        stopSync()
    }

    private func stopSync() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func localPlaybackFileName(for sound: AlarmSoundConfiguration) -> String {
        switch sound {
        case .systemDefault:
            return fallbackFileName
        case .bundled(let fileName):
            return fileName
        }
    }
}

enum AlarmAudioError: LocalizedError {
    case soundNotFound(String)

    var errorDescription: String? {
        switch self {
        case .soundNotFound(let name):
            return "Alarm sound '\(name)' was not found in the app bundle."
        }
    }
}
