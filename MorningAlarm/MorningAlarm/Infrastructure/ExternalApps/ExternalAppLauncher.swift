import Foundation
import UIKit

protocol ExternalAppLauncher: Sendable {
    /// Opens `destination` where possible. Never throws — a missing or
    /// unopenable app should fail silently, since opening it is a reward,
    /// not a requirement (description.md §16).
    func open(_ destination: AppDestination) async
}

@MainActor
final class SystemExternalAppLauncher: ExternalAppLauncher, @unchecked Sendable {
    func open(_ destination: AppDestination) async {
        guard let url = destination.launchURL, UIApplication.shared.canOpenURL(url) else { return }
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { _ in
                continuation.resume()
            }
        }
    }
}
