import Foundation

enum AlarmRuntimeState: Equatable {
    case idle
    /// Pre-alert gentle-wake countdown is playing softly (best effort,
    /// foreground only — see `AlarmAudioPlayer.playGentleWake`).
    case gentleWake(alarmID: UUID)
    case ringing(alarmID: UUID)
    case runningMission(alarmID: UUID, action: MissionAction)
    case snoozed(until: Date, alarmID: UUID)
    /// Turn-off mission just completed — showing "You're up!" + quote +
    /// optional post-alarm app trigger.
    case morningComplete(alarmID: UUID)
}

enum MissionAction: Equatable {
    case snooze
    case turnOff
}
