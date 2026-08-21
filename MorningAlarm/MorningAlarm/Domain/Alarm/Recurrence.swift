import Foundation

/// An empty `weekdays` set means "one-time" — the alarm fires once at the
/// next matching time and does not repeat.
struct Recurrence: Codable, Equatable {
    var weekdays: Set<Weekday>

    init(weekdays: Set<Weekday> = []) {
        self.weekdays = weekdays
    }

    static let never = Recurrence(weekdays: [])
    static let everyDay = Recurrence(weekdays: Set(Weekday.allCases))
    static let weekdaysOnly = Recurrence(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])
    static let weekendsOnly = Recurrence(weekdays: [.saturday, .sunday])

    var isRepeating: Bool { !weekdays.isEmpty }

    var summary: String {
        guard isRepeating else { return "Once" }
        if weekdays == Set(Weekday.allCases) { return "Every day" }
        if weekdays == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) { return "Weekdays" }
        if weekdays == Set([.saturday, .sunday]) { return "Weekends" }
        return Weekday.allCases
            .filter { weekdays.contains($0) }
            .map(\.shortSymbol)
            .joined(separator: " ")
    }

    /// Computes the next fire date honoring the configured weekdays. When
    /// `weekdays` is empty this is identical to a plain one-time next
    /// occurrence of `time`.
    func nextFireDate(for time: LocalTime, from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let firstCandidate = time.nextFireDate(from: reference, calendar: calendar)
        guard isRepeating else { return firstCandidate }

        var candidate = firstCandidate
        for _ in 0..<8 {
            if weekdays.contains(Weekday.from(date: candidate, calendar: calendar)) {
                return candidate
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return firstCandidate
    }
}
