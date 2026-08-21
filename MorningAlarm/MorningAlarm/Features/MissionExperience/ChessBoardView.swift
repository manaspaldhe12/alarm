import SwiftUI

struct ChessBoardView: View {
    let board: ChessBoard
    let selectedSquare: ChessSquare?
    let onTapSquare: (ChessSquare) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) / 8
            VStack(spacing: 0) {
                ForEach((0..<8).reversed(), id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { file in
                            squareView(file: file, rank: rank, size: size)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func squareView(file: Int, rank: Int, size: CGFloat) -> some View {
        let square = ChessSquare(file: file, rank: rank)
        ZStack {
            Rectangle()
                .fill(squareColor(file: file, rank: rank, isSelected: square == selectedSquare))
            if let piece = board.piece(at: square) {
                Text(symbol(for: piece))
                    .font(.system(size: size * 0.7))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { onTapSquare(square) }
    }

    private func squareColor(file: Int, rank: Int, isSelected: Bool) -> Color {
        if isSelected { return Color.yellow.opacity(0.6) }
        return (file + rank).isMultiple(of: 2) ? Color.brown.opacity(0.45) : Color.brown.opacity(0.15)
    }

    private func symbol(for piece: ChessPiece) -> String {
        switch (piece.color, piece.kind) {
        case (.white, .king): return "♔"
        case (.white, .queen): return "♕"
        case (.white, .rook): return "♖"
        case (.white, .bishop): return "♗"
        case (.white, .knight): return "♘"
        case (.white, .pawn): return "♙"
        case (.black, .king): return "♚"
        case (.black, .queen): return "♛"
        case (.black, .rook): return "♜"
        case (.black, .bishop): return "♝"
        case (.black, .knight): return "♞"
        case (.black, .pawn): return "♟"
        }
    }
}
