import XCTest
@testable import MorningAlarm

final class RepositoryTests: XCTestCase {
    func testFileAlarmRepositorySaveLoadDelete() async throws {
        let url = tempFileURL("alarms")
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = FileAlarmRepository(fileURL: url)

        var loaded = try await repo.alarms()
        XCTAssertEqual(loaded.count, 0, "a repository backed by a nonexistent file should start empty")

        let alarm = Alarm(time: LocalTime(hour: 7, minute: 0), label: "Test")
        try await repo.save(alarm)
        loaded = try await repo.alarms()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, alarm.id)

        var updated = alarm
        updated.label = "Updated"
        try await repo.save(updated)
        loaded = try await repo.alarms()
        XCTAssertEqual(loaded.count, 1, "saving with the same id should overwrite, not duplicate")
        XCTAssertEqual(loaded.first?.label, "Updated")

        try await repo.delete(id: alarm.id)
        loaded = try await repo.alarms()
        XCTAssertEqual(loaded.count, 0)
    }

    func testFileAlarmRepositoryPersistsAcrossInstances() async throws {
        let url = tempFileURL("alarms-persist")
        defer { try? FileManager.default.removeItem(at: url) }

        let alarm = Alarm(time: LocalTime(hour: 6, minute: 45), label: "Persisted")
        try await FileAlarmRepository(fileURL: url).save(alarm)

        // A brand new instance pointed at the same file should see the same data —
        // this is exactly what "survives app relaunch" depends on.
        let reloaded = try await FileAlarmRepository(fileURL: url).alarms()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.label, "Persisted")
    }

    func testFileQRCodeRepositoryRoundTrip() async throws {
        let url = tempFileURL("qr")
        defer { try? FileManager.default.removeItem(at: url) }
        let repo = FileQRCodeRepository(fileURL: url)

        let registration = try await repo.register(name: "Front Door", rawContent: "raw-payload-xyz")
        let all = try await repo.registrations()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, registration.id)

        let match = try await repo.matchingRegistration(rawContent: "raw-payload-xyz", requiredCodeID: nil)
        XCTAssertEqual(match?.id, registration.id)

        try await repo.delete(id: registration.id)
        let remaining = try await repo.registrations()
        XCTAssertEqual(remaining.count, 0)
    }

    func testWakeUpCheckStateStoreRoundTrip() async throws {
        let url = tempFileURL("wakeup-state")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WakeUpCheckStateStore(fileURL: url)

        let empty = await store.load()
        XCTAssertEqual(empty.count, 0)

        let checkID = UUID()
        let alarmID = UUID()
        await store.save([checkID: alarmID])

        let reloaded = await WakeUpCheckStateStore(fileURL: url).load()
        XCTAssertEqual(reloaded[checkID], alarmID, "mapping should survive being reloaded from a fresh store instance")
    }
}
