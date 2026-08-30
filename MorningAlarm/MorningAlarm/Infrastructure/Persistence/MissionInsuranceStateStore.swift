import Foundation

/// Persists which alarm (if any) currently has a mission genuinely in
/// progress -- i.e. the user tapped Snooze/Turn Off but hasn't finished the
/// mission yet.
///
/// Why this needs to survive a relaunch: `AlarmCoordinator.startMission`'s
/// insurance re-arm loop only exists as a `Task` inside the live process --
/// a force-quit kills it along with everything else. It re-arms AlarmKit's
/// native alert before dying, so the alert (and, via `syncAlertingAlarms`'s
/// poll loop, `presentRingingAlarm`) fires again shortly after -- but
/// without this store, that fresh process has no way to know the alarm was
/// already mid-mission, so it would just land back in a bare `.ringing`
/// state with no insurance loop running. If the user then swipes the app
/// away *again* without tapping a mission button first, nothing is left to
/// re-arm anything a second time and the alarm stays silent for good --
/// exactly the "swipe up once, it restarts; swipe up again, it doesn't"
/// gap this closes. `presentRingingAlarm` checks this on every ring and, if
/// set, immediately resumes the same mission (and its insurance coverage)
/// instead of waiting for the user to tap a button again.
actor MissionInsuranceStateStore {
    struct InProgressMission: Codable {
        let alarmID: UUID
        let action: MissionAction
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = directory.appendingPathComponent("MorningAlarm", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            self.fileURL = appDirectory.appendingPathComponent("mission_in_progress.json")
        }
    }

    func load() async -> InProgressMission? {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty,
            let decoded = try? decoder.decode(InProgressMission.self, from: data)
        else { return nil }
        return decoded
    }

    func save(_ mission: InProgressMission?) async {
        guard let mission else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? encoder.encode(mission) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
