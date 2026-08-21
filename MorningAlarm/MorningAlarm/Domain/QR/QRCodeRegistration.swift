import CryptoKit
import Foundation

/// A QR code the user has registered ahead of time (e.g. taped to the
/// bathroom mirror). Only a hash of the scanned payload is stored — never
/// the raw content — since the app only ever needs to check "does this scan
/// match a registration," not what the payload says.
struct QRCodeRegistration: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var contentHash: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, rawContent: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.contentHash = Self.hash(rawContent)
        self.createdAt = createdAt
    }

    static func hash(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func matches(rawContent: String) -> Bool {
        contentHash == Self.hash(rawContent)
    }
}
