import Foundation

protocol QRCodeRepository: Sendable {
    func registrations() async throws -> [QRCodeRegistration]
    func register(name: String, rawContent: String) async throws -> QRCodeRegistration
    func delete(id: UUID) async throws

    /// Returns the registration matching `rawContent`, honoring
    /// `requiredCodeID` when a mission is pinned to one specific code.
    func matchingRegistration(rawContent: String, requiredCodeID: UUID?) async throws -> QRCodeRegistration?
}

extension QRCodeRepository {
    func matchingRegistration(rawContent: String, requiredCodeID: UUID?) async throws -> QRCodeRegistration? {
        let all = try await registrations()
        if let requiredCodeID {
            return all.first { $0.id == requiredCodeID && $0.matches(rawContent: rawContent) }
        }
        return all.first { $0.matches(rawContent: rawContent) }
    }
}
