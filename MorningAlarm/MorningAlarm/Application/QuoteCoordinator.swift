import Foundation

@MainActor
final class QuoteCoordinator {
    private let repository: QuoteRepository
    private var lastQuoteID: String?

    init(repository: QuoteRepository) {
        self.repository = repository
    }

    func quote(for event: QuoteEvent) async -> Quote? {
        let quote = await repository.randomQuote(excluding: lastQuoteID)
        lastQuoteID = quote?.id
        return quote
    }
}
