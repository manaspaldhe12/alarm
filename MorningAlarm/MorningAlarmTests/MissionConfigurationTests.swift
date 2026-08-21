import XCTest
@testable import MorningAlarm

final class MissionConfigurationTests: XCTestCase {
    func testTypeMapping() {
        XCTAssertEqual(MissionConfiguration.none.type, .none)
        XCTAssertEqual(MissionConfiguration.steps(count: 10).type, .steps)
        XCTAssertEqual(MissionConfiguration.qrCode(codeID: nil).type, .qrCode)
        XCTAssertEqual(MissionConfiguration.chessPuzzle(minRating: 600, maxRating: 800, puzzleCount: 1).type, .chessPuzzle)
    }

    func testSummaries() {
        XCTAssertEqual(MissionConfiguration.none.summary, "No mission")
        XCTAssertEqual(MissionConfiguration.steps(count: 50).summary, "Walk 50 steps")
        XCTAssertEqual(MissionConfiguration.qrCode(codeID: nil).summary, "Scan any registered QR code")
        XCTAssertEqual(MissionConfiguration.chessPuzzle(minRating: 600, maxRating: 800, puzzleCount: 1).summary, "Solve 1 puzzle (600–800)")
        XCTAssertEqual(MissionConfiguration.chessPuzzle(minRating: 800, maxRating: 1000, puzzleCount: 2).summary, "Solve 2 puzzles (800–1000)")
    }

    func testCodableRoundTrip() throws {
        let configs: [MissionConfiguration] = [
            .none,
            .steps(count: 25),
            .qrCode(codeID: UUID()),
            .qrCode(codeID: nil),
            .chessPuzzle(minRating: 1200, maxRating: 1400, puzzleCount: 3),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for config in configs {
            let data = try encoder.encode(config)
            let decoded = try decoder.decode(MissionConfiguration.self, from: data)
            XCTAssertEqual(decoded, config, "round-trip through JSON should be lossless")
        }
    }

    func testAlarmCodableRoundTrip() throws {
        let alarm = Alarm(
            time: LocalTime(hour: 7, minute: 30),
            recurrence: Recurrence(weekdays: [.monday, .friday]),
            label: "Gym",
            enabled: true,
            gentleWake: GentleWakeConfiguration(enabled: true, durationMinutes: 15),
            snooze: SnoozeConfiguration(durationMinutes: 5, mission: .steps(count: 10), maxSnoozes: 3),
            turnOffMission: .chessPuzzle(minRating: 600, maxRating: 800, puzzleCount: 1),
            wakeUpCheck: WakeUpCheckConfiguration(enabled: true, delayMinutes: 15, mission: .steps(count: 50)),
            postAlarmAction: .weather
        )
        let data = try JSONEncoder().encode(alarm)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(decoded, alarm)
    }
}
