import Foundation

actor FileAlarmRepository: AlarmRepository {
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
            self.fileURL = appDirectory.appendingPathComponent("alarms.json")
        }
    }

    func alarms() async throws -> [Alarm] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([Alarm].self, from: data)
    }

    func save(_ alarm: Alarm) async throws {
        var allAlarms = try await alarms()
        if let index = allAlarms.firstIndex(where: { $0.id == alarm.id }) {
            allAlarms[index] = alarm
        } else {
            allAlarms.append(alarm)
        }
        try persist(allAlarms)
    }

    func delete(id: UUID) async throws {
        var allAlarms = try await alarms()
        allAlarms.removeAll { $0.id == id }
        try persist(allAlarms)
    }

    private func persist(_ alarms: [Alarm]) throws {
        let data = try encoder.encode(alarms)
        try data.write(to: fileURL, options: .atomic)
    }
}
