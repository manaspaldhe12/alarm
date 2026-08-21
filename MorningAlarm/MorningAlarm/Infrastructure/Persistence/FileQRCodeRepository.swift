import Foundation

actor FileQRCodeRepository: QRCodeRepository {
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
            self.fileURL = appDirectory.appendingPathComponent("qr_codes.json")
        }
    }

    func registrations() async throws -> [QRCodeRegistration] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([QRCodeRegistration].self, from: data)
    }

    func register(name: String, rawContent: String) async throws -> QRCodeRegistration {
        let registration = QRCodeRegistration(name: name, rawContent: rawContent)
        var all = try await registrations()
        all.append(registration)
        try persist(all)
        return registration
    }

    func delete(id: UUID) async throws {
        var all = try await registrations()
        all.removeAll { $0.id == id }
        try persist(all)
    }

    private func persist(_ registrations: [QRCodeRegistration]) throws {
        let data = try encoder.encode(registrations)
        try data.write(to: fileURL, options: .atomic)
    }
}
