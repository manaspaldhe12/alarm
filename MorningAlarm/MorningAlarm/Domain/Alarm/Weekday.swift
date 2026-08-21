import Foundation

/// Matches `Calendar`'s 1-based weekday numbering (1 = Sunday ... 7 = Saturday)
/// so it converts cleanly to/from `DateComponents.weekday` and `Locale.Weekday`.
enum Weekday: Int, Codable, CaseIterable, Comparable, Hashable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        let raw = calendar.component(.weekday, from: date)
        return Weekday(rawValue: raw) ?? .sunday
    }

    var shortSymbol: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var letterSymbol: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }
}
