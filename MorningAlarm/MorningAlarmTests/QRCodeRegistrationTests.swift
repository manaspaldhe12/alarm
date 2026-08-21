import XCTest
@testable import MorningAlarm

final class QRCodeRegistrationTests: XCTestCase {
    func testMatchesIdenticalContent() {
        let registration = QRCodeRegistration(name: "Bathroom", rawContent: "morning-alarm://bathroom-code-1")
        XCTAssertTrue(registration.matches(rawContent: "morning-alarm://bathroom-code-1"))
    }

    func testRejectsDifferentContent() {
        let registration = QRCodeRegistration(name: "Bathroom", rawContent: "morning-alarm://bathroom-code-1")
        XCTAssertFalse(registration.matches(rawContent: "morning-alarm://kitchen-code-1"))
    }

    func testDoesNotStoreRawContent() {
        let registration = QRCodeRegistration(name: "Bathroom", rawContent: "super-secret-payload")
        // The type only exposes contentHash/name/id/createdAt — there is no raw-content
        // property at all, which is itself the privacy guarantee. This test just pins that
        // the hash is not literally the raw string (i.e. hashing actually happened).
        XCTAssertNotEqual(registration.contentHash, "super-secret-payload")
        XCTAssertEqual(registration.contentHash.count, 64, "SHA256 hex digest should be 64 characters")
    }

    func testMatchingRegistrationHonorsRequiredCodeID() async throws {
        let repo = FakeQRCodeRepository()
        let bathroom = try await repo.register(name: "Bathroom", rawContent: "code-bathroom")
        _ = try await repo.register(name: "Kitchen", rawContent: "code-kitchen")

        let matchAny = try await repo.matchingRegistration(rawContent: "code-kitchen", requiredCodeID: nil)
        XCTAssertEqual(matchAny?.name, "Kitchen")

        let matchWrongRequired = try await repo.matchingRegistration(rawContent: "code-kitchen", requiredCodeID: bathroom.id)
        XCTAssertNil(matchWrongRequired, "scanning the kitchen code should not satisfy a mission pinned to the bathroom code")

        let matchCorrectRequired = try await repo.matchingRegistration(rawContent: "code-bathroom", requiredCodeID: bathroom.id)
        XCTAssertEqual(matchCorrectRequired?.id, bathroom.id)
    }
}
