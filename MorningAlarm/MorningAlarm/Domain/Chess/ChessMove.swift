import Foundation

struct ChessMove: Equatable {
    var from: ChessSquare
    var to: ChessSquare
    var promotion: PieceKind?

    init(from: ChessSquare, to: ChessSquare, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses coordinate/UCI notation, e.g. `"e2e4"` or `"e7e8q"`.
    init?(uci: String) {
        let chars = Array(uci)
        guard chars.count == 4 || chars.count == 5,
              let from = ChessSquare(algebraic: String(chars[0...1])),
              let to = ChessSquare(algebraic: String(chars[2...3]))
        else { return nil }

        self.from = from
        self.to = to

        if chars.count == 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: promotion = nil
            }
        } else {
            promotion = nil
        }
    }

    var uci: String {
        let promotionChar: String
        switch promotion {
        case .queen: promotionChar = "q"
        case .rook: promotionChar = "r"
        case .bishop: promotionChar = "b"
        case .knight: promotionChar = "n"
        case .pawn, .king, nil: promotionChar = ""
        }
        return from.algebraic + to.algebraic + promotionChar
    }
}
