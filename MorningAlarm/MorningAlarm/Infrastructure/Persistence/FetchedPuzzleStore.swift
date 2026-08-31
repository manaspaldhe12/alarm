import Foundation

/// Persists chess puzzles downloaded via `RemotePuzzleFetcher`, on top of
/// (never replacing) the read-only bundled `puzzles.json` set -- see
/// `BundledPuzzleRepository.fetchMorePuzzles`.
actor FetchedPuzzleStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirectory = directory.appendingPathComponent("MorningAlarm", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            self.fileURL = appDirectory.appendingPathComponent("fetched_puzzles.json")
        }
    }

    func load() async -> [Puzzle] {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            !data.isEmpty,
            let decoded = try? decoder.decode([Puzzle].self, from: data)
        else { return [] }
        return decoded
    }

    /// Merges `newPuzzles` into the persisted set, deduped by id (a repeat
    /// fetch will mostly overlap with what's already stored) -- returns how
    /// many were genuinely new, so the UI can report a meaningful count.
    @discardableResult
    func merge(_ newPuzzles: [Puzzle]) async -> Int {
        var existing = await load()
        let existingIDs = Set(existing.map(\.id))
        let fresh = newPuzzles.filter { !existingIDs.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }

        existing.append(contentsOf: fresh)
        guard let data = try? encoder.encode(existing) else { return 0 }
        try? data.write(to: fileURL, options: .atomic)
        return fresh.count
    }
}
