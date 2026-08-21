import Foundation

/// A single pedometer reading. `cumulativeSteps` mirrors `CMPedometerData`'s
/// `numberOfSteps`, i.e. the running total since observation started — not a
/// per-update delta.
struct StepUpdate: Sendable, Equatable {
    let timestamp: Date
    let cumulativeSteps: Int
}

/// Pure anti-cheat/step-acceptance logic, deliberately kept free of
/// CoreMotion so it can be unit tested with synthetic `StepUpdate` sequences.
///
/// This does not claim to perfectly detect cheating (see description.md
/// §22) — it just makes genuine walking clearly the easiest path:
/// - Steps only count once real pedometer-recognized deltas arrive.
/// - A cadence above `maximumStepsPerSecond` is treated as shaking, not
///   walking, and that batch is discarded.
/// - The mission can't complete before `minimumElapsedTime` has passed,
///   even if the target step count is already reported.
struct StepValidationEngine {
    var minimumElapsedTime: TimeInterval = 8
    var maximumStepsPerSecond: Double = 4.0

    private(set) var acceptedSteps: Int = 0
    private var startTime: Date?
    private var baselineCumulativeSteps: Int?
    private var lastUpdate: StepUpdate?

    init(minimumElapsedTime: TimeInterval = 8, maximumStepsPerSecond: Double = 4.0) {
        self.minimumElapsedTime = minimumElapsedTime
        self.maximumStepsPerSecond = maximumStepsPerSecond
    }

    mutating func start(at date: Date = Date()) {
        startTime = date
        baselineCumulativeSteps = nil
        lastUpdate = nil
        acceptedSteps = 0
    }

    @discardableResult
    mutating func accept(_ update: StepUpdate) -> Int {
        guard startTime != nil else { return acceptedSteps }

        guard let baseline = baselineCumulativeSteps, let previous = lastUpdate else {
            baselineCumulativeSteps = update.cumulativeSteps
            lastUpdate = update
            return acceptedSteps
        }

        let rawDelta = update.cumulativeSteps - previous.cumulativeSteps
        guard rawDelta > 0 else {
            lastUpdate = update
            return acceptedSteps
        }

        let elapsed = update.timestamp.timeIntervalSince(previous.timestamp)
        if elapsed > 0, Double(rawDelta) / elapsed > maximumStepsPerSecond {
            // Implausibly fast for walking — likely the phone being shaken.
            lastUpdate = update
            return acceptedSteps
        }

        acceptedSteps = max(acceptedSteps, update.cumulativeSteps - baseline)
        lastUpdate = update
        return acceptedSteps
    }

    func isComplete(target: Int, now: Date = Date()) -> Bool {
        guard let startTime else { return false }
        guard now.timeIntervalSince(startTime) >= minimumElapsedTime else { return false }
        return acceptedSteps >= target
    }
}
