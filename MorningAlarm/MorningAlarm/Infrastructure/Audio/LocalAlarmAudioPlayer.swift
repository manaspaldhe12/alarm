import AVFoundation
import Foundation

protocol AlarmAudioPlayer: Sendable {
    func playAlarmSound(_ sound: AlarmSoundConfiguration) throws
    func stop() async
}

final class LocalAlarmAudioPlayer: AlarmAudioPlayer, @unchecked Sendable {
    private var player: AVAudioPlayer?

    func playAlarmSound(_ sound: AlarmSoundConfiguration) throws {
        stopSync()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)

        guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: "wav") else {
            throw AlarmAudioError.soundNotFound(sound.fileName)
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = -1
        player.prepareToPlay()
        player.play()
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
