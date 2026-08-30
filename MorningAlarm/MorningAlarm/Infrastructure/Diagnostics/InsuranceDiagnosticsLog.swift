import Foundation

/// Persists a small rolling log of `AlarmCoordinator.startMission`'s
/// mission-insurance re-arm loop attempts.
///
/// Exists to answer one question that's otherwise unanswerable on a device
/// with no attached debugger: when a force-quit mid-mission leaves the
/// alarm silent, did the loop's `scheduler.schedule(...)` calls actually
/// succeed, and how recently before the app died? A real force-quit kills
/// the process before any UI could show that -- this survives it, so the
/// next launch can show what actually happened.
actor InsuranceDiagnosticsLog {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let attemptedAt: Date
        let targetFireDate: Date
        let outcome: String

        init(attemptedAt: Date, targetFireDate: Date, outcome: String) {
            self.id = UUID()
            self.attemptedAt = attemptedAt
            self.targetFireDate = targetFireDate
            self.outcome = outcome
        }
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxEntries = 50

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = directory.appendingPathComponent("MorningAlarm", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            self.fileURL = appDirectory.appendingPathComponent("insurance_diagnostics.json")
        }
    }

    func record(targetFireDate: Date, outcome: String) async {
        var entries = await load()
        entries.append(Entry(attemptedAt: Date(), targetFireDate: targetFireDate, outcome: outcome))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func load() async -> [Entry] {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty,
            let decoded = try? decoder.decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    func clear() async {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
