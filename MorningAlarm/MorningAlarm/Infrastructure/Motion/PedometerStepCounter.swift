import CoreMotion
import Foundation

final class PedometerStepCounter: StepCounter, @unchecked Sendable {
    func isAvailable() async -> Bool {
        CMPedometer.isStepCountingAvailable()
    }

    func observeSteps() -> AsyncStream<StepUpdate> {
        let pedometer = CMPedometer()
        return AsyncStream { continuation in
            pedometer.startUpdates(from: Date()) { data, error in
                guard let data, error == nil else { return }
                continuation.yield(StepUpdate(timestamp: data.endDate, cumulativeSteps: data.numberOfSteps.intValue))
            }
            continuation.onTermination = { _ in
                pedometer.stopUpdates()
            }
        }
    }
}
