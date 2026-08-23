import ActivityKit
import AlarmKit
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

        let alert = AlarmPresentation.Alert(
            title: "Good morning",
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<MorningAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: MorningAlarmMetadata(label: alarm.label),
            tintColor: .orange
        )

        let countdownDuration = AlarmKit.Alarm.CountdownDuration(
            preAlert: alarm.gentleWake.enabled ? alarm.gentleWake.duration : nil,
            postAlert: alarm.snooze.duration
        )
        let schedule = alarmKitSchedule(for: alarm, fireDate: fireDate)
        let sound = AlertConfiguration.AlertSound.named(alarm.sound.fileName)

        let configuration = Configuration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            sound: sound
        )

        try await manager.schedule(id: alarm.id, configuration: configuration)
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
