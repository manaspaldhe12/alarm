import Foundation
@testable import MorningAlarm

// Fakes conforming to the app's own protocols, used to exercise
// AlarmCoordinator/WakeUpCoordinator/MissionCoordinator's real logic without
// touching AlarmKit/CoreMotion/AVFoundation/UIKit in tests.

struct FakeError: Error, LocalizedError {
    let message: String
    init(_ message: String = "fake failure") { self.message = message }
    var errorDescription: String? { message }
}

final class FakeAlarmScheduler: AlarmScheduler, @unchecked Sendable {
    var authorizationResult: Bool = true
    private(set) var scheduledCalls: [(alarm: Alarm, fireDate: Date?)] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    var alerting: Set<UUID> = []
    var countdown: Set<UUID> = []
    /// Debug state to report per alarm ID — see `debugState(for:)`. `nil`
    /// for an ID not in this dictionary, matching "AlarmKit has no record
    /// of this alarm at all".
    var debugStates: [UUID: String] = [:]
    /// Alarm IDs for which `schedule(_:fireDate:)` should throw instead of
    /// succeeding, to test failure-handling paths.
    var scheduleFailureIDs: Set<UUID> = []

    func requestAuthorizationIfNeeded() async throws -> Bool { authorizationResult }

    func schedule(_ alarm: Alarm, fireDate: Date?) async throws {
        if scheduleFailureIDs.contains(alarm.id) {
            throw FakeError("schedule() failed for \(alarm.id)")
        }
        scheduledCalls.append((alarm, fireDate))
    }

    func cancel(alarmID: UUID) async throws {
        cancelledIDs.append(alarmID)
    }

    func stop(alarmID: UUID) async throws {
        stoppedIDs.append(alarmID)
        alerting.remove(alarmID)
        countdown.remove(alarmID)
    }

    func alertingAlarmIDs() async -> [UUID] { Array(alerting) }
    func countdownAlarmIDs() async -> [UUID] { Array(countdown) }
    func debugState(for alarmID: UUID) async -> String? { debugStates[alarmID] }
}

final class FakeAlarmAudioPlayer: AlarmAudioPlayer, @unchecked Sendable {
    private(set) var playedSounds: [AlarmSoundConfiguration] = []
    private(set) var playedGentleWakeSounds: [AlarmSoundConfiguration] = []
    private(set) var stopCount = 0

    func playAlarmSound(_ sound: AlarmSoundConfiguration) throws {
        playedSounds.append(sound)
    }

    func playGentleWake(_ sound: AlarmSoundConfiguration, rampDuration: TimeInterval) throws {
        playedGentleWakeSounds.append(sound)
    }

    func stop() async {
        stopCount += 1
    }
}

actor FakeAlarmRepository: AlarmRepository {
    private var storage: [UUID: Alarm] = [:]
    /// IDs for which `delete(id:)` should throw instead of succeeding, to
    /// test failure-handling paths.
    private var deleteFailureIDs: Set<UUID> = []

    func setDeleteFailure(for id: UUID) {
        deleteFailureIDs.insert(id)
    }

    func alarms() async throws -> [Alarm] { Array(storage.values) }

    func save(_ alarm: Alarm) async throws {
        storage[alarm.id] = alarm
    }

    func delete(id: UUID) async throws {
        if deleteFailureIDs.contains(id) {
            throw FakeError("delete() failed for \(id)")
        }
        storage[id] = nil
    }
}

final class FakeExternalAppLauncher: ExternalAppLauncher, @unchecked Sendable {
    private(set) var openedDestinations: [AppDestination] = []

    func open(_ destination: AppDestination) async {
        openedDestinations.append(destination)
    }
}

final class FakeQuoteRepository: QuoteRepository, @unchecked Sendable {
    let quotes: [Quote]

    init(quotes: [Quote]) {
        self.quotes = quotes
    }

    func randomQuote(excluding lastID: String?) async -> Quote? {
        guard !quotes.isEmpty else { return nil }
        guard quotes.count > 1 else { return quotes.first }
        let candidates = quotes.filter { $0.id != lastID }
        return (candidates.isEmpty ? quotes : candidates).first
    }
}

final class FakeStepCounter: StepCounter, @unchecked Sendable {
    /// Pre-scripted updates, yielded one at a time as `observeSteps()` is consumed.
    var scriptedUpdates: [StepUpdate] = []
    var available = true
    /// A real (wall-clock) delay in nanoseconds between yields, so tests
    /// exercising `StepValidationEngine`'s minimum-elapsed-time gate (which
    /// reads the real clock, not `StepUpdate.timestamp`) can actually
    /// satisfy it.
    var realDelayBetweenUpdatesNanoseconds: UInt64 = 0

    func isAvailable() async -> Bool { available }

    func observeSteps() -> AsyncStream<StepUpdate> {
        let updates = scriptedUpdates
        let delay = realDelayBetweenUpdatesNanoseconds
        return AsyncStream { continuation in
            Task {
                for update in updates {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }
    }
}

final class FakeQRCodeRepository: QRCodeRepository, @unchecked Sendable {
    private(set) var registered: [QRCodeRegistration] = []

    func registrations() async throws -> [QRCodeRegistration] { registered }

    func register(name: String, rawContent: String) async throws -> QRCodeRegistration {
        let registration = QRCodeRegistration(name: name, rawContent: rawContent)
        registered.append(registration)
        return registration
    }

    func delete(id: UUID) async throws {
        registered.removeAll { $0.id == id }
    }
}

final class FakePuzzleRepository: PuzzleRepository, @unchecked Sendable {
    var puzzlesToReturn: [Puzzle] = []

    func puzzles(minRating: Int, maxRating: Int, count: Int) async throws -> [Puzzle] {
        let matching = puzzlesToReturn.filter { $0.rating >= minRating && $0.rating <= maxRating }
        guard !matching.isEmpty else { throw PuzzleRepositoryError.noPuzzlesInRange }
        return Array(matching.prefix(count))
    }
}

func tempFileURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
}
