import Foundation

struct Alarm: Identifiable, Codable, Equatable {
    let id: UUID
    var time: LocalTime
    var recurrence: Recurrence
    var label: String
    var enabled: Bool
    var sound: AlarmSoundConfiguration
    var gentleWake: GentleWakeConfiguration
    var snooze: SnoozeConfiguration
    var turnOffMission: MissionConfiguration
    var wakeUpCheck: WakeUpCheckConfiguration
    var postAlarmAction: AppDestination

    init(
        id: UUID = UUID(),
        time: LocalTime,
        recurrence: Recurrence = .never,
        label: String = "Alarm",
        enabled: Bool = true,
        sound: AlarmSoundConfiguration = .default,
        gentleWake: GentleWakeConfiguration = .default,
        snooze: SnoozeConfiguration = .default,
        turnOffMission: MissionConfiguration = .defaultTurnOff,
        wakeUpCheck: WakeUpCheckConfiguration = .default,
        postAlarmAction: AppDestination = .none
    ) {
        self.id = id
        self.time = time
        self.recurrence = recurrence
        self.label = label
        self.enabled = enabled
        self.sound = sound
        self.gentleWake = gentleWake
        self.snooze = snooze
        self.turnOffMission = turnOffMission
        self.wakeUpCheck = wakeUpCheck
        self.postAlarmAction = postAlarmAction
    }

    func nextFireDate(from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        recurrence.nextFireDate(for: time, from: reference, calendar: calendar)
    }
}
