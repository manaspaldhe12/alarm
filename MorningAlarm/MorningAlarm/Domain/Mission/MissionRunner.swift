import Foundation

/// The piece of logic that actually carries out one mission attempt
/// (counting steps, scanning a QR code, validating a chess puzzle). Runners
/// know nothing about alarms, snoozing, or SwiftUI — they just report
/// progress and eventually resolve to a `MissionResult`.
///
/// Cooperative cancellation: implementations should periodically check
/// `Task.isCancelled` (or use cancellable async APIs) and return `.cancelled`
/// promptly when cancelled.
protocol MissionRunner: Sendable {
    func run(reportProgress: @escaping @Sendable (MissionProgress) -> Void) async -> MissionResult
}

/// A runner for `.none` — resolves immediately.
struct NoMissionRunner: MissionRunner {
    func run(reportProgress: @escaping @Sendable (MissionProgress) -> Void) async -> MissionResult {
        .completed
    }
}
