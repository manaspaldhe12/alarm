import Foundation

enum PieceColor: String, Codable, Equatable {
    case white
    case black

    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceKind: String, Codable, Equatable {
    case pawn, knight, bishop, rook, queen, king
}

struct ChessPiece: Equatable {
    var kind: PieceKind
    var color: PieceColor
}
