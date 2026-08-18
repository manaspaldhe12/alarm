import AppIntents
import Foundation

struct OpenAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Open Alarm"
    static var description = IntentDescription("Opens the alarm screen in Morning Alarm.")
    static var openAppWhenRun = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .alarmOpenedFromSystem,
            object: nil,
            userInfo: ["alarmID": alarmID]
        )
        return .result()
    }
}

extension Notification.Name {
    static let alarmOpenedFromSystem = Notification.Name("alarmOpenedFromSystem")
}
