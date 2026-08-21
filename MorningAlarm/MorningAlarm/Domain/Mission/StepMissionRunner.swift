import Foundation

struct StepMissionRunner: MissionRunner {
    let targetSteps: Int
    let stepCounter: StepCounter
    var minimumElapsedTime: TimeInterval = 8
    var maximumStepsPerSecond: Double = 4.0

    func run(reportProgress: @escaping @Sendable (MissionProgress) -> Void) async -> MissionResult {
        guard targetSteps > 0 else { return .completed }
        guard await stepCounter.isAvailable() else {
            return .failed(reason: "Step counting isn't available on this device.")
        }

        var engine = StepValidationEngine(
            minimumElapsedTime: minimumElapsedTime,
            maximumStepsPerSecond: maximumStepsPerSecond
        )
        engine.start()

        reportProgress(MissionProgress(fraction: 0, statusText: "0 / \(targetSteps) steps"))

        for await update in stepCounter.observeSteps() {
            if Task.isCancelled { return .cancelled }

            let accepted = engine.accept(update)
            let fraction = Double(accepted) / Double(targetSteps)
            reportProgress(MissionProgress(
                fraction: fraction,
                statusText: "\(min(accepted, targetSteps)) / \(targetSteps) steps"
            ))

            if engine.isComplete(target: targetSteps) {
                return .completed
            }
        }

        return .cancelled
    }
}
