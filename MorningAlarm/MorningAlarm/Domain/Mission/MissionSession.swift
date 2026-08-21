import Foundation
import Observation

/// The single, generic, observable "a mission is currently in progress"
/// object that every mission UI (steps / QR / chess) binds to. The UI and
/// the rest of the app only ever see this type — never the concrete runner.
@MainActor
@Observable
final class MissionSession {
    let configuration: MissionConfiguration
    private(set) var progress: MissionProgress = .idle
    private(set) var result: MissionResult?

    /// `nil` for interactive missions (QR, chess) whose content view drives
    /// completion directly via `updateProgress`/`complete`/`fail` — there's
    /// no headless async computation to run since they need live UI (a
    /// camera preview, a tappable board).
    private let runner: MissionRunner?
    private var task: Task<Void, Never>?

    init(configuration: MissionConfiguration, runner: MissionRunner? = nil) {
        self.configuration = configuration
        self.runner = runner
    }

    var isRunning: Bool { result == nil }

    func updateProgress(_ progress: MissionProgress) {
        self.progress = progress
    }

    func complete() {
        result = .completed
    }

    func fail(reason: String) {
        result = .failed(reason: reason)
    }

    func start() {
        guard let runner, task == nil else { return }
        task = Task { [weak self] in
            let outcome = await runner.run { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.result = outcome
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if result == nil {
            result = .cancelled
        }
    }
}
