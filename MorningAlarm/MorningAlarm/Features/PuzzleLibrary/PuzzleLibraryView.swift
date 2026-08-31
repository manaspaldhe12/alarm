import SwiftUI

/// Lets the user explicitly download a larger chess puzzle pool -- the one
/// deliberate exception to this app's offline-first design (see
/// `BundledPuzzleRepository.fetchMorePuzzles`). Reachable only from the
/// alarm list, never from an active alarm/mission.
struct PuzzleLibraryView: View {
    let puzzleRepository: BundledPuzzleRepository

    @Environment(\.dismiss) private var dismiss
    @State private var puzzleCount: Int?
    @State private var isFetching = false
    @State private var resultMessage: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Puzzles available") {
                        if let puzzleCount {
                            Text("\(puzzleCount)")
                        } else {
                            ProgressView()
                        }
                    }
                }

                Section {
                    Text("Chess-mission puzzles are bundled with the app and always work offline — that's what every alarm actually relies on. Fetching more is optional: it downloads an additional batch over the internet and adds it to your library for next time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await fetchMore() }
                    } label: {
                        if isFetching {
                            HStack {
                                ProgressView()
                                Text("Fetching…")
                            }
                        } else {
                            Text("Fetch More Puzzles")
                        }
                    }
                    .disabled(isFetching)

                    if let resultMessage {
                        Text(resultMessage)
                            .font(.footnote)
                            .foregroundStyle(isError ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Puzzle Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reloadCount() }
        }
    }

    private func reloadCount() async {
        puzzleCount = await puzzleRepository.puzzleCount()
    }

    private func fetchMore() async {
        isFetching = true
        resultMessage = nil
        isError = false
        do {
            let added = try await puzzleRepository.fetchMorePuzzles()
            resultMessage = added > 0
                ? "Added \(added) new puzzle\(added == 1 ? "" : "s")."
                : "No new puzzles — you already have the whole batch."
        } catch {
            isError = true
            resultMessage = error.localizedDescription
        }
        await reloadCount()
        isFetching = false
    }
}
