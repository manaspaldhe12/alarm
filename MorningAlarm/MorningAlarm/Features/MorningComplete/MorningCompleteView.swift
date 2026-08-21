import SwiftUI

/// Shown both after the turn-off mission completes and after the wake-up
/// check completes — "you're up," a quote, and an optional (never required)
/// reason to keep the phone in hand.
struct MorningCompleteView: View {
    let headline: String
    let quote: Quote?
    let postAlarmAction: AppDestination
    let onOpenApp: () -> Void
    let onDone: () -> Void

    init(
        headline: String = "You're up! ☀️",
        quote: Quote?,
        postAlarmAction: AppDestination = .none,
        onOpenApp: @escaping () -> Void = {},
        onDone: @escaping () -> Void
    ) {
        self.headline = headline
        self.quote = quote
        self.postAlarmAction = postAlarmAction
        self.onOpenApp = onOpenApp
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.35), Color.yellow.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text(headline)
                    .font(.largeTitle.weight(.bold))

                if let quote {
                    Text("\u{201C}\(quote.text)\u{201D}")
                        .font(.title3)
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 32)
                }

                Spacer()

                if postAlarmAction != .none {
                    Button {
                        onOpenApp()
                        onDone()
                    } label: {
                        Text("Open \(postAlarmAction.displayName) →")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                }

                Button("Continue", action: onDone)
                    .padding(.bottom, 40)
            }
        }
    }
}
