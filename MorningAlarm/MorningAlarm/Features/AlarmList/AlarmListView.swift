import SwiftUI

struct AlarmListView: View {
    @Bindable var coordinator: AlarmCoordinator
    let qrCodeRepository: QRCodeRepository
    let missionCoordinator: MissionCoordinator
    let stepCounter: StepCounter

    @State private var showingEditor = false
    @State private var editingAlarm: Alarm?
    @State private var showingQRSetup = false
    @State private var showingTestMissions = false
    @State private var showingInsuranceLog = false
    @State private var debugStates: [UUID: String] = [:]

    /// A fixed, stable id for the editor sheet's "New Alarm" case — see the
    /// `.id(...)` on the sheet below.
    private static let newAlarmSheetID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

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
                                    editingAlarm = alarm
                                    showingEditor = true
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingAlarm = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                AlarmEditorView(
                    alarm: editingAlarm,
                    qrCodeRepository: qrCodeRepository,
                    onSave: { alarm in
                        Task {
                            await coordinator.updateAlarm(alarm)
                        }
                    }
                )
                // Without an explicit identity, SwiftUI can reuse this sheet's
                // @State storage across separate presentations (e.g. "New
                // Alarm" defaulting to 7 AM, then editing some other,
                // disabled alarm afterward) since it's structurally the same
                // view each time -- keying on which alarm (or "new", a fixed
                // sentinel -- NOT a freshly-generated UUID, which would
                // recompute on every body re-render and reset in-progress
                // form state constantly) is being edited forces a fresh
                // @State init from the actual alarm's saved time every time,
                // matching AlarmEditorView.init's own (already-correct) logic.
                .id(editingAlarm?.id ?? AlarmListView.newAlarmSheetID)
            }
            .sheet(isPresented: $showingTestMissions) {
                TestMissionView(missionCoordinator: missionCoordinator, stepCounter: stepCounter)
            }
            .sheet(isPresented: $showingInsuranceLog) {
                InsuranceDiagnosticsView(diagnostics: coordinator.insuranceDiagnostics)
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
        stepCounter: container.stepCounter
    )
}
