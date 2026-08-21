import Foundation

enum QuoteCategory: String, Codable, CaseIterable, Identifiable {
    case wakeUp, exercise, work, discipline, focus, persistence, morning, humor, general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wakeUp: return "Wake Up"
        case .exercise: return "Exercise"
        case .work: return "Work"
        case .discipline: return "Discipline"
        case .focus: return "Focus"
        case .persistence: return "Persistence"
        case .morning: return "Morning"
        case .humor: return "Humor"
        case .general: return "General Motivation"
        }
    }
}

struct Quote: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let category: QuoteCategory
}

enum QuoteEvent {
    case snoozed
    case alarmCompleted
    case wakeUpCheckCompleted
}
