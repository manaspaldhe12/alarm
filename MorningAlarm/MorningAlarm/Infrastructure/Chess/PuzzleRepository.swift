import Foundation

protocol PuzzleRepository: Sendable {
    func puzzles(minRating: Int, maxRating: Int, count: Int) async throws -> [Puzzle]
}

enum PuzzleRepositoryError: LocalizedError {
    case noPuzzlesInRange

    var errorDescription: String? {
        "No puzzles are available in that difficulty range."
    }
}

/// Loads the bundled, offline `puzzles.json` dataset once at init. No
/// network access — matches the "no request while the alarm is active"
/// requirement trivially, since there's never a request at all.
final class BundledPuzzleRepository: PuzzleRepository, @unchecked Sendable {
    private let allPuzzles: [Puzzle]

    init(bundle: Bundle = .main) {
        if
            let url = bundle.url(forResource: "puzzles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Puzzle].self, from: data)
        {
            allPuzzles = decoded
        } else {
            allPuzzles = []
        }
    }

    func puzzles(minRating: Int, maxRating: Int, count: Int) async throws -> [Puzzle] {
        let matching = allPuzzles.filter { $0.rating >= minRating && $0.rating <= maxRating }
        guard !matching.isEmpty else { throw PuzzleRepositoryError.noPuzzlesInRange }
        return Array(matching.shuffled().prefix(max(1, count)))
    }
}
