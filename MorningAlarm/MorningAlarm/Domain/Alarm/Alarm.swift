import Foundation

struct Alarm: Identifiable, Codable, Equatable {
    let id: UUID
    var time: LocalTime
    var label: String
    var enabled: Bool
    var sound: AlarmSoundConfiguration
    var snooze: SnoozeConfiguration

    init(
        id: UUID = UUID(),
        time: LocalTime,
        label: String = "Alarm",
        enabled: Bool = true,
        sound: AlarmSoundConfiguration = .default,
        snooze: SnoozeConfiguration = .default
    ) {
        self.id = id
        self.time = time
        self.label = label
        self.enabled = enabled
        self.sound = sound
        self.snooze = snooze
    }
}
