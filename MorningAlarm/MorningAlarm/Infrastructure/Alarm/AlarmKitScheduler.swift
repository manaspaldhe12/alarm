import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI

/// Bridges our domain `Alarm` model to AlarmKit's own `Alarm` types.
///
/// Both this app's domain model and the AlarmKit framework export a type
/// named `Alarm`. Swift always resolves a bare `Alarm` to the type declared
/// in this module (our domain model), so every reference to AlarmKit's
/// `Alarm` namespace below is explicitly qualified as `AlarmKit.Alarm` to
/// avoid picking up the wrong type.
final class AlarmKitScheduler: AlarmScheduler, @unchecked Sendable {
    private let manager = AlarmManager.shared

    func requestAuthorizationIfNeeded() async throws -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    func schedule(_ alarm: Alarm, fireDate: Date?) async throws {
        let configuration = makeConfiguration(
            resumingAlarmID: alarm.id,
            label: alarm.label,
            sound: alarm.sound,
            preAlert: alarm.gentleWake.enabled ? alarm.gentleWake.duration : nil,
            postAlert: alarm.snooze.duration,
            schedule: alarmKitSchedule(for: alarm, fireDate: fireDate)
        )
        try await manager.schedule(id: alarm.id, configuration: configuration)
    }

    func scheduleShadowInsurance(shadowID: UUID, for alarm: Alarm, fireDate: Date) async throws {
        // No gentle wake -- a shadow only ever exists to bring the user back
        // to a mission already in progress, never as a first ring.
        let configuration = makeConfiguration(
            resumingAlarmID: alarm.id,
            label: alarm.label,
            sound: alarm.sound,
            preAlert: nil,
            postAlert: alarm.snooze.duration,
            schedule: .fixed(fireDate)
        )
        try await manager.schedule(id: shadowID, configuration: configuration)
    }

    /// Shared by `schedule(_:fireDate:)` and `scheduleShadowInsurance` --
    /// `resumingAlarmID` is the domain alarm the stop/secondary intents open
    /// the app back to, which is deliberately *not* always the same as the
    /// id this configuration gets registered under (see
    /// `scheduleShadowInsurance`'s doc comment).
    private func makeConfiguration(
        resumingAlarmID: UUID,
        label: String,
        sound soundConfig: AlarmSoundConfiguration,
        preAlert: TimeInterval?,
        postAlert: TimeInterval,
        schedule: AlarmKit.Alarm.Schedule
    ) -> AlarmManager.AlarmConfiguration<MorningAlarmMetadata> {
        typealias Configuration = AlarmManager.AlarmConfiguration<MorningAlarmMetadata>

        let stopButton = AlarmButton(
            text: "Turn Off",
            textColor: .white,
            systemImageName: "checkmark.circle"
        )

        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "clock.arrow.circlepath"
        )

        // .countdown (AlarmKit's own native snooze) and omitting stopIntent
        // both hand the button taps entirely to AlarmKit itself -- neither
        // one ever reaches AlarmCoordinator, which is exactly how "Turn Off"
        // and "Snooze" were able to dismiss the alarm with no mission gating
        // at all. .custom + explicit stopIntent/secondaryIntent (below, in
        // the Configuration) route both taps through OpenAlarmIntent instead,
        // which only opens the app to the mission-gated ringing screen and
        // does not itself stop or snooze anything.
        let alert = AlarmPresentation.Alert(
            title: "Good morning",
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes<MorningAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: MorningAlarmMetadata(label: label),
            tintColor: .orange
        )

        let countdownDuration = AlarmKit.Alarm.CountdownDuration(preAlert: preAlert, postAlert: postAlert)

        let sound: AlertConfiguration.AlertSound
        switch soundConfig {
        case .systemDefault:
            sound = .default
        case .bundled(let fileName):
            sound = .named("\(fileName).wav")
        }

        let openIntent = OpenAlarmIntent(alarmID: resumingAlarmID.uuidString)

        return Configuration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: openIntent,
            secondaryIntent: openIntent,
            sound: sound
        )
    }

    func cancel(alarmID: UUID) async throws {
        try await manager.cancel(id: alarmID)
    }

    func stop(alarmID: UUID) async throws {
        try await manager.stop(id: alarmID)
    }

    func alertingAlarmIDs() async -> [UUID] {
        let alarms = (try? manager.alarms) ?? []
        return alarms.compactMap { scheduled in
            switch scheduled.state {
            case .alerting:
                return scheduled.id
            default:
                return nil
            }
        }
    }

    func countdownAlarmIDs() async -> [UUID] {
        let alarms = (try? manager.alarms) ?? []
        return alarms.compactMap { scheduled in
            switch scheduled.state {
            case .countdown:
                return scheduled.id
            default:
                return nil
            }
        }
    }

    func debugState(for alarmID: UUID) async -> String? {
        guard let scheduled = (try? manager.alarms)?.first(where: { $0.id == alarmID }) else {
            return nil
        }
        // Deliberately not switching on specific cases here -- this exists
        // precisely because we don't have full confidence in every
        // `AlarmKit.Alarm.State` case name, and a generic description is
        // safer than guessing wrong ones for a diagnostics-only string.
        return String(describing: scheduled.state)
    }

    /// - `fireDate` provided: a one-shot override (used for snoozing).
    /// - `fireDate` nil, repeating alarm: a native weekly-repeating AlarmKit schedule.
    /// - `fireDate` nil, one-time alarm: the next matching one-shot occurrence.
    private func alarmKitSchedule(for alarm: Alarm, fireDate: Date?) -> AlarmKit.Alarm.Schedule {
        if let fireDate {
            return .fixed(fireDate)
        }

        guard alarm.recurrence.isRepeating else {
            return .fixed(alarm.nextFireDate())
        }

        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.time.hour, minute: alarm.time.minute)
        let days = alarm.recurrence.weekdays.sorted().map(\.asLocaleWeekday)
        return .relative(.init(time: time, repeats: .weekly(days)))
    }
}

private extension Weekday {
    var asLocaleWeekday: Locale.Weekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }
}
