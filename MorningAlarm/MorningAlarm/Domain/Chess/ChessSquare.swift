import Foundation

/// `file`/`rank` are both 0-based (0...7), matching `a`...`h` and `1`...`8`.
struct ChessSquare: Equatable, Hashable {
    var file: Int
    var rank: Int

    init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    init?(algebraic: String) {
        let chars = Array(algebraic)
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue,
              let rankValue = chars[1].wholeNumberValue
        else { return nil }

        let file = Int(fileAscii) - Int(aAscii)
        let rank = rankValue - 1
        guard (0...7).contains(file), (0...7).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    var algebraic: String {
        guard let aAscii = Character("a").asciiValue else { return "" }
        let fileChar = Character(UnicodeScalar(UInt8(file) + aAscii))
        return "\(fileChar)\(rank + 1)"
    }
}
