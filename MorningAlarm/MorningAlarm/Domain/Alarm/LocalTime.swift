import Foundation

struct LocalTime: Codable, Equatable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    func nextFireDate(from reference: Date = Date(), calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else {
            return reference.addingTimeInterval(60)
        }

        if candidate <= reference {
            return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }

        return candidate
    }

    var formatted: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            return String(format: "%d:%02d", hour, minute)
        }

        return date.formatted(date: .omitted, time: .shortened)
    }
}
