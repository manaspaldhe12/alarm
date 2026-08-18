import AlarmKit
import Foundation
import SwiftUI

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

    func schedule(_ alarm: Alarm, fireDate: Date) async throws {
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
            secondaryButtonBehavior: .snooze
        )

        let attributes = AlarmAttributes<MorningAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: MorningAlarmMetadata(label: alarm.label),
            tintColor: .orange
        )

        let countdownDuration = Alarm.CountdownDuration(postAlert: alarm.snooze.duration)
        let schedule = Alarm.Schedule.fixed(fireDate)
        let sound = AlertConfiguration.AlertSound.named(alarm.sound.fileName)

        let configuration = Configuration(
            schedule: schedule,
            countdownDuration: countdownDuration,
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
        manager.alarms.compactMap { scheduled in
            switch scheduled.state {
            case .alert:
                return scheduled.id
            default:
                return nil
            }
        }
    }
}
