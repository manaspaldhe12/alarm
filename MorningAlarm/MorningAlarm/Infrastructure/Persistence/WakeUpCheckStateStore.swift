import Foundation

/// Persists the mapping of pending wake-up-check alarm IDs to the original
/// alarm they belong to, so it survives app relaunch — the check may fire
/// many minutes after the app that scheduled it was closed.
actor WakeUpCheckStateStore {
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
            self.fileURL = appDirectory.appendingPathComponent("wake_up_checks.json")
        }
    }

    func load() async -> [UUID: UUID] {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty,
            let decoded = try? decoder.decode([UUID: UUID].self, from: data)
        else { return [:] }
        return decoded
    }

    func save(_ mapping: [UUID: UUID]) async {
        guard let data = try? encoder.encode(mapping) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
