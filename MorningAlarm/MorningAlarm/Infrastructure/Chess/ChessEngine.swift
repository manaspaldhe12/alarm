import Foundation

/// Deliberately validates against the puzzle's known-correct solution
/// sequence rather than implementing full chess legality (check detection,
/// pins, stalemate, etc.). Per description.md §11/§22 the goal is "just
/// enough cognitive engagement," not a correspondence chess engine — and a
/// full legal-move generator is a large surface area to get right without
/// meaningfully improving the wake-up experience.
protocol ChessEngine: Sendable {
    func validate(move: ChessMove, puzzle: Puzzle, solvedMoveCount: Int) -> Bool
}

struct LocalChessEngine: ChessEngine {
    func validate(move: ChessMove, puzzle: Puzzle, solvedMoveCount: Int) -> Bool {
        guard solvedMoveCount < puzzle.solution.count else { return false }
        guard let expected = ChessMove(uci: puzzle.solution[solvedMoveCount]) else { return false }
        return expected.from == move.from && expected.to == move.to && expected.promotion == move.promotion
    }
}
