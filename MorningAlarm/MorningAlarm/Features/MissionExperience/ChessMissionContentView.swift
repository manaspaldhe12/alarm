import SwiftUI

struct ChessMissionContentView: View {
    let session: MissionSession
    let puzzleRepository: PuzzleRepository
    let engine: ChessEngine

    @State private var puzzles: [Puzzle] = []
    @State private var puzzleIndex = 0
    @State private var board: ChessBoard?
    @State private var solvedMoveCount = 0
    @State private var selectedSquare: ChessSquare?
    @State private var message = "Loading puzzle…"
    @State private var isLocked = false

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let board {
                Text("\(board.sideToMove == .white ? "White" : "Black") to move")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        board.sideToMove == .white ? Color.white : Color.black,
                        in: Capsule()
                    )
                    .foregroundStyle(board.sideToMove == .white ? .black : .white)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.3)))
            }

            if let board {
                ChessBoardView(board: board, selectedSquare: selectedSquare, onTapSquare: handleTap)
                    .frame(width: 300, height: 300)
                    .disabled(isLocked)
            } else {
                ProgressView()
                    .frame(width: 300, height: 300)
            }
        }
        .task { await loadPuzzles() }
    }

    private func loadPuzzles() async {
        guard case .chessPuzzle(let minRating, let maxRating, let puzzleCount) = session.configuration else { return }
        do {
            puzzles = try await puzzleRepository.puzzles(minRating: minRating, maxRating: maxRating, count: puzzleCount)
            startPuzzle(at: 0)
        } catch {
            session.fail(reason: "No puzzles available in that range.")
        }
    }

    private func startPuzzle(at index: Int) {
        guard index < puzzles.count else {
            session.complete()
            return
        }
        puzzleIndex = index
        board = ChessBoard(fen: puzzles[index].fen)
        solvedMoveCount = 0
        selectedSquare = nil
        message = "Puzzle \(index + 1) of \(puzzles.count). Find the best move."
        session.updateProgress(MissionProgress(
            fraction: Double(index) / Double(puzzles.count),
            statusText: "\(index) / \(puzzles.count) solved"
        ))
    }

    private func handleTap(_ square: ChessSquare) {
        guard !isLocked, var board, puzzleIndex < puzzles.count else { return }
        let puzzle = puzzles[puzzleIndex]

        if let from = selectedSquare {
            selectedSquare = nil
            let move = ChessMove(from: from, to: square, promotion: promotionIfNeeded(from: from, to: square, board: board))

            if engine.validate(move: move, puzzle: puzzle, solvedMoveCount: solvedMoveCount) {
                board.apply(move)
                self.board = board
                solvedMoveCount += 1
                message = "Nice."

                if solvedMoveCount >= puzzle.solution.count {
                    advanceAfterDelay()
                } else {
                    playOpponentReply(puzzle: puzzle)
                }
            } else if board.piece(at: square)?.color == puzzle.sideToMove {
                selectedSquare = square
            } else {
                message = "Not quite. Try again."
            }
        } else if board.piece(at: square)?.color == puzzle.sideToMove {
            selectedSquare = square
        }
    }

    private func promotionIfNeeded(from: ChessSquare, to: ChessSquare, board: ChessBoard) -> PieceKind? {
        guard let piece = board.piece(at: from), piece.kind == .pawn else { return nil }
        if (piece.color == .white && to.rank == 7) || (piece.color == .black && to.rank == 0) {
            return .queen
        }
        return nil
    }

    private func playOpponentReply(puzzle: Puzzle) {
        guard solvedMoveCount < puzzle.solution.count,
              let reply = ChessMove(uci: puzzle.solution[solvedMoveCount])
        else { return }

        isLocked = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if var board {
                board.apply(reply)
                self.board = board
            }
            solvedMoveCount += 1
            isLocked = false

            if solvedMoveCount >= puzzle.solution.count {
                advanceAfterDelay()
            } else {
                message = "Your move."
            }
        }
    }

    private func advanceAfterDelay() {
        isLocked = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isLocked = false
            startPuzzle(at: puzzleIndex + 1)
        }
    }
}
