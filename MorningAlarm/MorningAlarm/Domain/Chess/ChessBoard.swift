import Foundation

/// A minimal board representation used only to *render* puzzle positions and
/// play out a known-correct move sequence — not a legal-move generator. See
/// `ChessEngine` for why full legality checking is intentionally out of
/// scope for a wake-up mission.
struct ChessBoard: Equatable {
    private(set) var squares: [ChessSquare: ChessPiece] = [:]
    private(set) var sideToMove: PieceColor

    init(fen: String) {
        let fields = fen.split(separator: " ")
        sideToMove = (fields.count > 1 && fields[1] == "b") ? .black : .white

        guard let placement = fields.first else { return }
        var rank = 7
        var file = 0
        for char in placement {
            if char == "/" {
                rank -= 1
                file = 0
            } else if let emptyCount = char.wholeNumberValue {
                file += emptyCount
            } else {
                if let piece = Self.piece(for: char) {
                    squares[ChessSquare(file: file, rank: rank)] = piece
                }
                file += 1
            }
        }
    }

    func piece(at square: ChessSquare) -> ChessPiece? {
        squares[square]
    }

    /// Applies a trusted move (no legality checking). Handles capture,
    /// castling (king moving two files also moves the rook), en passant (a
    /// pawn moving diagonally onto an empty square removes the pawn behind
    /// the destination), and promotion.
    mutating func apply(_ move: ChessMove) {
        guard let moving = squares[move.from] else { return }

        if moving.kind == .pawn, move.from.file != move.to.file, squares[move.to] == nil {
            squares[ChessSquare(file: move.to.file, rank: move.from.rank)] = nil
        }

        if moving.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file > move.from.file {
                squares[ChessSquare(file: 5, rank: rank)] = squares[ChessSquare(file: 7, rank: rank)]
                squares[ChessSquare(file: 7, rank: rank)] = nil
            } else {
                squares[ChessSquare(file: 3, rank: rank)] = squares[ChessSquare(file: 0, rank: rank)]
                squares[ChessSquare(file: 0, rank: rank)] = nil
            }
        }

        squares[move.from] = nil
        if let promotion = move.promotion {
            squares[move.to] = ChessPiece(kind: promotion, color: moving.color)
        } else {
            squares[move.to] = moving
        }

        sideToMove = sideToMove.opposite
    }

    private static func piece(for char: Character) -> ChessPiece? {
        let color: PieceColor = char.isUppercase ? .white : .black
        switch Character(char.lowercased()) {
        case "p": return ChessPiece(kind: .pawn, color: color)
        case "n": return ChessPiece(kind: .knight, color: color)
        case "b": return ChessPiece(kind: .bishop, color: color)
        case "r": return ChessPiece(kind: .rook, color: color)
        case "q": return ChessPiece(kind: .queen, color: color)
        case "k": return ChessPiece(kind: .king, color: color)
        default: return nil
        }
    }
}
