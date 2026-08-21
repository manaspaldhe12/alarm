import SwiftUI

struct AlarmListView: View {
    @Bindable var coordinator: AlarmCoordinator
    let qrCodeRepository: QRCodeRepository

    @State private var showingEditor = false
    @State private var editingAlarm: Alarm?
    @State private var showingQRSetup = false

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
                                onToggle: { enabled in
                                    Task {
                                        await coordinator.setEnabled(enabled, for: alarm.id)
                                    }
                                },
                                onTap: {
                                    editingAlarm = alarm
                                    showingEditor = true
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
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingQRSetup = true
                    } label: {
                        Image(systemName: "qrcode")
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
    let onToggle: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.time.formatted)
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()

                Text("\(alarm.label) · \(alarm.recurrence.summary)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
    }
}

#Preview {
    let container = AppDependencyContainer.make()
    AlarmListView(coordinator: container.alarmCoordinator, qrCodeRepository: container.qrCodeRepository)
}
