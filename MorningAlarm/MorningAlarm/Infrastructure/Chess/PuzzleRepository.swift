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

/// Loads the bundled, offline `puzzles.json` dataset once at init -- always
/// available with zero network access, which is what every mission actually
/// relies on. `fetchMorePuzzles()` is a separate, explicit, user-triggered
/// exception to that (see its own doc comment) that only ever *adds* to the
/// pool `puzzles(minRating:maxRating:count:)` draws from; it's never called
/// automatically and never sits on the alarm-dismissal path.
final class BundledPuzzleRepository: PuzzleRepository, @unchecked Sendable {
    private let allBundledPuzzles: [Puzzle]
    private let fetchedStore: FetchedPuzzleStore
    private let remoteFetcher: RemotePuzzleFetcher

    init(
        bundle: Bundle = .main,
        fetchedStore: FetchedPuzzleStore = FetchedPuzzleStore(),
        remoteFetcher: RemotePuzzleFetcher = URLSessionRemotePuzzleFetcher()
    ) {
        if
            let url = bundle.url(forResource: "puzzles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Puzzle].self, from: data)
        {
            allBundledPuzzles = decoded
        } else {
            allBundledPuzzles = []
        }
        self.fetchedStore = fetchedStore
        self.remoteFetcher = remoteFetcher
    }

    func puzzles(minRating: Int, maxRating: Int, count: Int) async throws -> [Puzzle] {
        let fetched = await fetchedStore.load()
        let matching = (allBundledPuzzles + fetched).filter { $0.rating >= minRating && $0.rating <= maxRating }
        guard !matching.isEmpty else { throw PuzzleRepositoryError.noPuzzlesInRange }
        return Array(matching.shuffled().prefix(max(1, count)))
    }

    /// Total puzzles currently available (bundled + previously fetched),
    /// for `PuzzleLibraryView` to display.
    func puzzleCount() async -> Int {
        allBundledPuzzles.count + (await fetchedStore.load()).count
    }

    /// Downloads a fresh batch of puzzles and merges any new ones into the
    /// persisted, on-top-of-bundled pool. Requires network access -- the one
    /// deliberate exception to this app's offline-first design, reachable
    /// only from `PuzzleLibraryView` (not from any alarm/mission flow).
    /// Returns how many were genuinely new (a repeat fetch will mostly
    /// overlap with what's already stored).
    @discardableResult
    func fetchMorePuzzles() async throws -> Int {
        let downloaded = try await remoteFetcher.fetchPuzzles()
        return await fetchedStore.merge(downloaded)
    }
}
