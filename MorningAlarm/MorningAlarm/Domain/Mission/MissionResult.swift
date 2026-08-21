import Foundation

enum MissionResult: Equatable {
    case completed
    case cancelled
    case failed(reason: String)
}

struct MissionProgress: Equatable {
    var fraction: Double
    var statusText: String

    static let idle = MissionProgress(fraction: 0, statusText: "")

    init(fraction: Double, statusText: String) {
        self.fraction = min(1, max(0, fraction))
        self.statusText = statusText
    }
}
