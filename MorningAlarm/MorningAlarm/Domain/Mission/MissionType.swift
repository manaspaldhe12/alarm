import Foundation

enum MissionType: String, Codable, CaseIterable, Hashable, Identifiable {
    case none
    case steps
    case qrCode
    case chessPuzzle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .steps: return "Steps"
        case .qrCode: return "QR Code"
        case .chessPuzzle: return "Chess Puzzle"
        }
    }
}
