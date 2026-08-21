import Foundation

protocol StepCounter: Sendable {
    func isAvailable() async -> Bool

    /// Cumulative step readings from the moment this stream is created until
    /// it's cancelled/terminated. Each element carries the running total, not
    /// a delta, mirroring `CMPedometerData.numberOfSteps`.
    func observeSteps() -> AsyncStream<StepUpdate>
}
