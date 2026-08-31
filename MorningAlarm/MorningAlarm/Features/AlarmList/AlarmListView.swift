import SwiftUI

/// What the editor sheet is presenting -- either a brand new alarm, or an
/// existing one. Driving `.sheet(item:)` off this (instead of the more
/// common `.sheet(isPresented:)` paired with a separate `Alarm?`) means
/// SwiftUI's own `Identifiable`-keyed view identity handles "give me a
/// genuinely fresh AlarmEditorView per distinct target" for us, rather than
/// a hand-maintained `.id(...)` doing the same job less reliably: `.sheet(
/// item:)` both keys identity off the *actual* item (so two different
/// targets can never accidentally share stale @State) and automatically
/// clears the bound value to `nil` on dismiss/cancel, which the previous
/// `editingAlarm` state never did on its own.
private enum EditorTarget: Identifiable {
    case new
    case existing(Alarm)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let alarm): return alarm.id.uuidString
        }
    }

    var alarm: Alarm? {
        switch self {
        case .new: return nil
        case .existing(let alarm): return alarm
        }
    }
}

struct AlarmListView: View {
    @Bindable var coordinator: AlarmCoordinator
    let qrCodeRepository: QRCodeRepository
    let missionCoordinator: MissionCoordinator
    let stepCounter: StepCounter
    let puzzleLibrary: BundledPuzzleRepository

    @State private var editorTarget: EditorTarget?
    @State private var showingQRSetup = false
    @State private var showingTestMissions = false
    @State private var showingInsuranceLog = false
    @State private var showingPuzzleLibrary = false
    @State private var debugStates: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.alarms.isEmpty {
                    ContentUnavailableView(
                        "No Alarms",
                        systemImage: "alarm",
                        description: Text("Tap + to create your first alarm.")
                    )
                } else {
                    List {
                        ForEach(coordinator.alarms) { alarm in
                            AlarmRowView(
                                alarm: alarm,
                                debugState: debugStates[alarm.id],
                                onToggle: { enabled in
                                    Task {
                                        await coordinator.setEnabled(enabled, for: alarm.id)
                                    }
                                },
                                onTap: {
                                    editorTarget = .existing(alarm)
                                },
                                onTestRingNow: {
                                    Task {
                                        await coordinator.presentRingingAlarm(alarm.id)
                                    }
                                }
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let alarm = coordinator.alarms[index]
                                Task { await coordinator.deleteAlarm(id: alarm.id) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .task {
                // Diagnostics only: periodically ask the real scheduler what
                // it actually believes about each alarm, so "is this really
                // scheduled?" is answerable without a device console.
                while !Task.isCancelled {
                    for alarm in coordinator.alarms {
                        debugStates[alarm.id] = await coordinator.debugState(for: alarm.id)
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingQRSetup = true
                    } label: {
                        Image(systemName: "qrcode")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingTestMissions = true
                    } label: {
                        Image(systemName: "testtube.2")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingInsuranceLog = true
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPuzzleLibrary = true
                    } label: {
                        Image(systemName: "square.grid.3x3.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                AlarmEditorView(
                    alarm: target.alarm,
                    qrCodeRepository: qrCodeRepository,
                    onSave: { alarm in
                        Task {
                            await coordinator.updateAlarm(alarm)
                        }
                    }
                )
            }
            .sheet(isPresented: $showingTestMissions) {
                TestMissionView(missionCoordinator: missionCoordinator, stepCounter: stepCounter)
            }
            .sheet(isPresented: $showingInsuranceLog) {
                InsuranceDiagnosticsView(diagnostics: coordinator.insuranceDiagnostics)
            }
            .sheet(isPresented: $showingPuzzleLibrary) {
                PuzzleLibraryView(puzzleRepository: puzzleLibrary)
            }
            .sheet(isPresented: $showingQRSetup) {
                QRSetupView(repository: qrCodeRepository)
            }
            .overlay(alignment: .bottom) {
                if let message = coordinator.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.9), in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

struct AlarmRowView: View {
    let alarm: Alarm
    var debugState: String?
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    var onTestRingNow: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.time.formatted)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()

                Text("\(alarm.label) · \(alarm.recurrence.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if alarm.enabled {
                    Text("AlarmKit: \(debugState ?? "not scheduled")")
                        .font(.caption2)
                        .foregroundStyle(debugState == nil ? .red : .secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { alarm.enabled },
                set: onToggle
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.vertical, 4)
        .contextMenu {
            if let onTestRingNow {
                Button {
                    onTestRingNow()
                } label: {
                    Label("Test Ring Now", systemImage: "bell.badge")
                }
            }
        }
    }
}

#Preview {
    let container = AppDependencyContainer.make()
    AlarmListView(
        coordinator: container.alarmCoordinator,
        qrCodeRepository: container.qrCodeRepository,
        missionCoordinator: container.missionCoordinator,
        stepCounter: container.stepCounter,
        puzzleLibrary: container.puzzleLibrary
    )
}
