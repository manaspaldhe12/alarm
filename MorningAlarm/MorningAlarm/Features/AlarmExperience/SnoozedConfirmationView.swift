import SwiftUI

struct SnoozedConfirmationView: View {
    let until: Date
    let quote: Quote?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)

                Text("Snoozed until \(until.formatted(date: .omitted, time: .shortened))")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                if let quote {
                    Text("\u{201C}\(quote.text)\u{201D}")
                        .font(.subheadline)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 32)
                }

                Button("OK", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 8)
            }
            .padding(32)
        }
    }
}
