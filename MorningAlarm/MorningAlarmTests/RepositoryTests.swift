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

    private func makePuzzle(_ id: String, rating: Int = 1000) -> Puzzle {
        Puzzle(id: id, rating: rating, fen: "8/8/8/8/8/8/8/K6k w - - 0 1", sideToMove: .white, solution: ["a1a2"])
    }

    func testFetchedPuzzleStoreMergeDedupesById() async {
        let url = tempFileURL("fetched-puzzles")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FetchedPuzzleStore(fileURL: url)

        let addedFirst = await store.merge([makePuzzle("p1"), makePuzzle("p2")])
        XCTAssertEqual(addedFirst, 2)

        // Re-fetching the same batch (plus one genuinely new one) should only count the new one.
        let addedSecond = await store.merge([makePuzzle("p1"), makePuzzle("p2"), makePuzzle("p3")])
        XCTAssertEqual(addedSecond, 1, "re-merging already-stored ids should not be counted as new")

        let all = await store.load()
        XCTAssertEqual(Set(all.map(\.id)), ["p1", "p2", "p3"], "the store itself must not contain duplicates either")
    }

    func testFetchedPuzzleStorePersistsAcrossInstances() async {
        let url = tempFileURL("fetched-puzzles-persist")
        defer { try? FileManager.default.removeItem(at: url) }

        await FetchedPuzzleStore(fileURL: url).merge([makePuzzle("persisted")])

        let reloaded = await FetchedPuzzleStore(fileURL: url).load()
        XCTAssertEqual(reloaded.map(\.id), ["persisted"])
    }

    func testBundledPuzzleRepositoryFetchMorePuzzlesAddsToPool() async throws {
        let fetchedStoreURL = tempFileURL("fetched-for-repo")
        defer { try? FileManager.default.removeItem(at: fetchedStoreURL) }
        let fetcher = FakeRemotePuzzleFetcher()
        fetcher.puzzlesToReturn = [makePuzzle("remote1", rating: 1500), makePuzzle("remote2", rating: 1500)]

        let repository = BundledPuzzleRepository(
            fetchedStore: FetchedPuzzleStore(fileURL: fetchedStoreURL),
            remoteFetcher: fetcher
        )

        let countBefore = await repository.puzzleCount()
        let added = try await repository.fetchMorePuzzles()
        XCTAssertEqual(added, 2)
        XCTAssertEqual(fetcher.fetchCount, 1)

        let countAfter = await repository.puzzleCount()
        XCTAssertEqual(countAfter, countBefore + 2, "fetched puzzles must add to, not replace, the bundled pool")

        let matching = try await repository.puzzles(minRating: 1500, maxRating: 1500, count: 10)
        XCTAssertEqual(Set(matching.map(\.id)), ["remote1", "remote2"], "puzzles() should draw from newly-fetched puzzles too, not just the bundled set")
    }

    func testBundledPuzzleRepositoryFetchMorePuzzlesPropagatesError() async {
        let fetcher = FakeRemotePuzzleFetcher()
        fetcher.errorToThrow = RemotePuzzleFetchError.badResponse(500)
        let repository = BundledPuzzleRepository(
            fetchedStore: FetchedPuzzleStore(fileURL: tempFileURL("fetched-error")),
            remoteFetcher: fetcher
        )

        do {
            _ = try await repository.fetchMorePuzzles()
            XCTFail("expected the fetcher's error to propagate")
        } catch {
            XCTAssertTrue(error is RemotePuzzleFetchError)
        }
    }
}
