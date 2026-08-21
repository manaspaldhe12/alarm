import XCTest
@testable import MorningAlarm

@MainActor
final class QuoteCoordinatorTests: XCTestCase {
    func testAvoidsImmediateRepeatAcrossCalls() async {
        let quotes = [
            Quote(id: "a", text: "A", category: .general),
            Quote(id: "b", text: "B", category: .general),
        ]
        let coordinator = QuoteCoordinator(repository: FakeQuoteRepository(quotes: quotes))

        let first = await coordinator.quote(for: .snoozed)
        let second = await coordinator.quote(for: .alarmCompleted)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.id, second?.id, "the coordinator should track the last shown quote and avoid repeating it immediately")
    }

    func testReturnsNilWhenNoQuotesBundled() async {
        let coordinator = QuoteCoordinator(repository: FakeQuoteRepository(quotes: []))
        let quote = await coordinator.quote(for: .snoozed)
        XCTAssertNil(quote)
    }

    func testSingleQuoteRepeatsWhenOnlyOneExists() async {
        let quotes = [Quote(id: "only", text: "Only one", category: .general)]
        let coordinator = QuoteCoordinator(repository: FakeQuoteRepository(quotes: quotes))
        let first = await coordinator.quote(for: .snoozed)
        let second = await coordinator.quote(for: .alarmCompleted)
        XCTAssertEqual(first?.id, "only")
        XCTAssertEqual(second?.id, "only")
    }
}
