import Foundation

/// A destination offered as a positive reason to get up — never a
/// requirement for dismissing the alarm. `urlScheme` is the app's own URL
/// (used to check whether it's installed / to open it); `fallbackURL` is
/// used when there's no dedicated scheme to probe (e.g. `x-apple-...` system
/// apps that don't need one).
enum AppDestination: String, Codable, CaseIterable, Hashable, Identifiable {
    case none
    case calendar
    case weather
    case reminders
    case music
    case fitness
    case news
    case stocks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .reminders: return "Reminders"
        case .music: return "Music"
        case .fitness: return "Fitness"
        case .news: return "News"
        case .stocks: return "Stocks"
        }
    }

    /// System apps' `x-apple-*` URL schemes are stable and don't require an
    /// installed-app check the way third-party schemes would.
    var launchURL: URL? {
        switch self {
        case .none: return nil
        case .calendar: return URL(string: "calshow://")
        case .weather: return URL(string: "x-apple-weather://")
        case .reminders: return URL(string: "x-apple-reminderkit://")
        case .music: return URL(string: "music://")
        case .fitness: return URL(string: "x-apple-fitness://")
        case .news: return URL(string: "applenews://")
        case .stocks: return URL(string: "stocks://")
        }
    }
}
