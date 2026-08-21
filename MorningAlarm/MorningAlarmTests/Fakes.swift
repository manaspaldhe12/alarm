import Foundation
@testable import MorningAlarm

// Fakes conforming to the app's own protocols, used to exercise
// AlarmCoordinator/WakeUpCoordinator/MissionCoordinator's real logic without
// touching AlarmKit/CoreMotion/AVFoundation/UIKit in tests.

final class FakeAlarmScheduler: AlarmScheduler, @unchecked Sendable {
    var authorizationResult: Bool = true
    private(set) var scheduledCalls: [(alarm: Alarm, fireDate: Date?)] = []
    private(set) var cancelledIDs: [UUID] = []
    private(set) var stoppedIDs: [UUID] = []
    var alerting: Set<UUID> = []
    var countdown: Set<UUID> = []

    func requestAuthorizationIfNeeded() async throws -> Bool { authorizationResult }

    func schedule(_ alarm: Alarm, fireDate: Date?) async throws {
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

    func alarms() async throws -> [Alarm] { Array(storage.values) }

    func save(_ alarm: Alarm) async throws {
        storage[alarm.id] = alarm
    }

    func delete(id: UUID) async throws {
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
