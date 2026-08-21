import Foundation

/// What a specific alarm action (snooze / turn-off / wake-up check) requires
/// the user to do. `.none` means the action completes instantly with no
/// mission — used for snooze-without-a-mission or when a feature is disabled.
enum MissionConfiguration: Codable, Equatable {
    case none
    case steps(count: Int)
    case qrCode(codeID: UUID?)
    case chessPuzzle(minRating: Int, maxRating: Int, puzzleCount: Int)

    var type: MissionType {
        switch self {
        case .none: return .none
        case .steps: return .steps
        case .qrCode: return .qrCode
        case .chessPuzzle: return .chessPuzzle
        }
    }

    var summary: String {
        switch self {
        case .none:
            return "No mission"
        case .steps(let count):
            return "Walk \(count) steps"
        case .qrCode(let codeID):
            return codeID == nil ? "Scan any registered QR code" : "Scan a specific QR code"
        case .chessPuzzle(let minRating, let maxRating, let puzzleCount):
            let puzzleWord = puzzleCount == 1 ? "puzzle" : "puzzles"
            return "Solve \(puzzleCount) \(puzzleWord) (\(minRating)–\(maxRating))"
        }
    }

    static let defaultSnooze = MissionConfiguration.steps(count: 10)
    static let defaultTurnOff = MissionConfiguration.steps(count: 50)
    static let defaultWakeUpCheck = MissionConfiguration.steps(count: 50)
}
