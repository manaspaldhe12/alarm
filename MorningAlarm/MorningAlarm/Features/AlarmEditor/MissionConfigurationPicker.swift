import SwiftUI

/// A reusable "what does the user have to do" picker, shared by the
/// snooze, turn-off, and wake-up-check sections of the alarm editor.
struct MissionConfigurationPicker: View {
    let title: String
    @Binding var configuration: MissionConfiguration
    let qrCodeRepository: QRCodeRepository
    var allowNone = false

    @State private var registrations: [QRCodeRegistration] = []

    var body: some View {
        Section(title) {
            Picker("Type", selection: typeBinding) {
                if allowNone { Text("None").tag(MissionType.none) }
                Text("Steps").tag(MissionType.steps)
                Text("QR Code").tag(MissionType.qrCode)
                Text("Chess Puzzle").tag(MissionType.chessPuzzle)
            }

            missionDetail
        }
        .task {
            registrations = (try? await qrCodeRepository.registrations()) ?? []
        }
    }

    @ViewBuilder
    private var missionDetail: some View {
        switch configuration {
        case .none:
            EmptyView()

        case .steps(let count):
            Stepper("Walk \(count) steps", value: stepsBinding(), in: 5...500, step: 5)

        case .qrCode:
            if registrations.isEmpty {
                Text("No QR codes registered yet. Add one from the QR icon on the alarm list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Code", selection: qrCodeBinding()) {
                    Text("Any registered code").tag(UUID?.none)
                    ForEach(registrations) { registration in
                        Text(registration.name).tag(UUID?.some(registration.id))
                    }
                }
            }

        case .chessPuzzle(_, _, let puzzleCount):
            Picker("Difficulty", selection: bandBinding()) {
                ForEach(RatingBand.allCases, id: \.self) { band in
                    Text(band.label).tag(band)
                }
            }
            Stepper("\(puzzleCount) \(puzzleCount == 1 ? "puzzle" : "puzzles")", value: countBinding(), in: 1...5)
        }
    }

    private var typeBinding: Binding<MissionType> {
        Binding(
            get: { configuration.type },
            set: { newType in
                switch newType {
                case .none: configuration = .none
                case .steps: configuration = .steps(count: 50)
                case .qrCode: configuration = .qrCode(codeID: nil)
                case .chessPuzzle: configuration = .chessPuzzle(minRating: 600, maxRating: 800, puzzleCount: 1)
                }
            }
        )
    }

    private func stepsBinding() -> Binding<Int> {
        Binding(
            get: {
                if case .steps(let count) = configuration { return count }
                return 50
            },
            set: { configuration = .steps(count: $0) }
        )
    }

    private func qrCodeBinding() -> Binding<UUID?> {
        Binding(
            get: {
                if case .qrCode(let codeID) = configuration { return codeID }
                return nil
            },
            set: { configuration = .qrCode(codeID: $0) }
        )
    }

    private func bandBinding() -> Binding<RatingBand> {
        Binding(
            get: {
                guard case .chessPuzzle(let minRating, _, _) = configuration else { return .b600 }
                return RatingBand.allCases.first { $0.range.lowerBound == minRating } ?? .b600
            },
            set: { newBand in
                guard case .chessPuzzle(_, _, let count) = configuration else { return }
                configuration = .chessPuzzle(minRating: newBand.range.lowerBound, maxRating: newBand.range.upperBound, puzzleCount: count)
            }
        )
    }

    private func countBinding() -> Binding<Int> {
        Binding(
            get: {
                if case .chessPuzzle(_, _, let count) = configuration { return count }
                return 1
            },
            set: { newCount in
                guard case .chessPuzzle(let minRating, let maxRating, _) = configuration else { return }
                configuration = .chessPuzzle(minRating: minRating, maxRating: maxRating, puzzleCount: newCount)
            }
        )
    }
}

enum RatingBand: CaseIterable, Hashable {
    case b600, b800, b1000, b1200, b1400, b1600, b1800

    var range: ClosedRange<Int> {
        switch self {
        case .b600: return 600...800
        case .b800: return 800...1000
        case .b1000: return 1000...1200
        case .b1200: return 1200...1400
        case .b1400: return 1400...1600
        case .b1600: return 1600...1800
        case .b1800: return 1800...2600
        }
    }

    var label: String {
        switch self {
        case .b600: return "600–800"
        case .b800: return "800–1000"
        case .b1000: return "1000–1200"
        case .b1200: return "1200–1400"
        case .b1400: return "1400–1600"
        case .b1600: return "1600–1800"
        case .b1800: return "1800+"
        }
    }
}
