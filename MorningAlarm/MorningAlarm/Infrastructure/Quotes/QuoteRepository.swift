import Foundation

protocol QuoteRepository: Sendable {
    /// Picks a random quote, avoiding `lastID` when more than one is
    /// available so the same line doesn't show twice in a row.
    func randomQuote(excluding lastID: String?) async -> Quote?
}

final class BundledQuoteRepository: QuoteRepository, @unchecked Sendable {
    private let quotes: [Quote]

    init(bundle: Bundle = .main) {
        if
            let url = bundle.url(forResource: "quotes", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Quote].self, from: data)
        {
            quotes = decoded
        } else {
            quotes = []
        }
    }

    func randomQuote(excluding lastID: String?) async -> Quote? {
        guard !quotes.isEmpty else { return nil }
        guard quotes.count > 1 else { return quotes.first }
        let candidates = quotes.filter { $0.id != lastID }
        return (candidates.isEmpty ? quotes : candidates).randomElement()
    }
}
