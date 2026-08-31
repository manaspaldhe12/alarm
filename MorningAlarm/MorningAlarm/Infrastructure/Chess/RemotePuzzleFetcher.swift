import Foundation

/// The one deliberate exception to this app's offline-first design: an
/// explicit, user-triggered download of a larger chess puzzle pool. Never
/// called automatically, and never reachable from an active alarm/mission --
/// see `BundledPuzzleRepository.fetchMorePuzzles` and `PuzzleLibraryView`.
protocol RemotePuzzleFetcher: Sendable {
    func fetchPuzzles() async throws -> [Puzzle]
}

enum RemotePuzzleFetchError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let statusCode):
            return "Couldn't download new puzzles (server returned \(statusCode)). Check your connection and try again."
        }
    }
}

final class URLSessionRemotePuzzleFetcher: RemotePuzzleFetcher, @unchecked Sendable {
    /// A larger, non-overlapping pool of puzzles converted from the same
    /// source (Lichess's CC0-licensed puzzle database) as the bundled set,
    /// hosted as a plain static JSON file in this project's own repo --
    /// Lichess's own API only exposes one fixed puzzle per day without
    /// OAuth, which isn't useful for "fetch a fresh batch now".
    static let defaultURL = URL(string: "https://raw.githubusercontent.com/manaspaldhe12/alarm/main/puzzle-data/remote_puzzles.json")!

    private let url: URL
    private let session: URLSession

    init(url: URL = URLSessionRemotePuzzleFetcher.defaultURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func fetchPuzzles() async throws -> [Puzzle] {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RemotePuzzleFetchError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode([Puzzle].self, from: data)
    }
}
