import SwiftUI

struct QRMissionContentView: View {
    let session: MissionSession
    let repository: QRCodeRepository

    @State private var statusMessage = "Scan your registered code"
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)
                .frame(height: 280)
                .overlay(
                    ZStack {
                        QRScannerView(onDetect: handleDetection)
                        ScannerFrameOverlay()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                )
                .padding(.horizontal, 24)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func handleDetection(_ rawContent: String) {
        guard !isChecking, case .qrCode(let requiredCodeID) = session.configuration else { return }
        isChecking = true

        Task {
            do {
                if let match = try await repository.matchingRegistration(rawContent: rawContent, requiredCodeID: requiredCodeID) {
                    statusMessage = "\(match.name) — got it!"
                    session.complete()
                } else {
                    statusMessage = "That's not the right code. Keep looking."
                    isChecking = false
                }
            } catch {
                statusMessage = "Couldn't verify that code. Try again."
                isChecking = false
            }
        }
    }
}
