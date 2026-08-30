import SwiftUI

/// Debug-only screen for `InsuranceDiagnosticsLog` — see that type's doc
/// comment for why it exists. Reachable from `AlarmListView`'s toolbar.
struct InsuranceDiagnosticsView: View {
    let diagnostics: InsuranceDiagnosticsLog

    @State private var entries: [InsuranceDiagnosticsLog.Entry] = []

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No insurance re-arm attempts logged yet. Start a mission (tap Snooze or Turn Off while an alarm is ringing) to generate entries, then check back here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("attempted \(entry.attemptedAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                            Text("target fire: \(entry.targetFireDate.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.outcome)
                                .font(.caption2)
                                .foregroundStyle(entry.outcome.hasPrefix("failed") ? .red : .green)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Insurance Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        Task {
                            await diagnostics.clear()
                            entries = []
                        }
                    }
                    .disabled(entries.isEmpty)
                }
            }
            .task {
                entries = await diagnostics.load()
            }
            .refreshable {
                entries = await diagnostics.load()
            }
        }
    }
}
