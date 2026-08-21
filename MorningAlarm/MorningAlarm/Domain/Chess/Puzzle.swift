import Foundation

/// `solution` is UCI/coordinate notation. Even indices (0, 2, ...) are moves
/// the player must find; odd indices are the opponent's forced reply, which
/// the app auto-plays.
struct Puzzle: Codable, Equatable, Identifiable {
    let id: String
    let rating: Int
    let fen: String
    let sideToMove: PieceColor
    let solution: [String]
}
