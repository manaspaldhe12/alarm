import Foundation

/// A quiet-to-full volume ramp that starts before the main alarm time.
/// Implemented via AlarmKit's pre-alert countdown (see `AlarmKitScheduler`)
/// so it survives the app being backgrounded or terminated just like the
/// main alarm does.
struct GentleWakeConfiguration: Codable, Equatable {
    var enabled: Bool
    var durationMinutes: Int

    static let `default` = GentleWakeConfiguration(enabled: false, durationMinutes: 10)

    var duration: TimeInterval { TimeInterval(durationMinutes * 60) }
}
