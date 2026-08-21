import SwiftUI

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let alarm: Alarm?
    let qrCodeRepository: QRCodeRepository
    let onSave: (Alarm) -> Void

    @State private var selectedDate: Date
    @State private var label: String
    @State private var enabled: Bool
    @State private var selectedWeekdays: Set<Weekday>

    @State private var gentleWakeEnabled: Bool
    @State private var gentleWakeMinutes: Int

    @State private var snoozeMinutes: Int
    @State private var snoozeMission: MissionConfiguration
    @State private var unlimitedSnoozes: Bool
    @State private var maxSnoozes: Int

    @State private var turnOffMission: MissionConfiguration

    @State private var wakeUpCheckEnabled: Bool
    @State private var wakeUpCheckDelayMinutes: Int
    @State private var wakeUpCheckMission: MissionConfiguration

    @State private var postAlarmAction: AppDestination

    init(alarm: Alarm?, qrCodeRepository: QRCodeRepository, onSave: @escaping (Alarm) -> Void) {
        self.alarm = alarm
        self.qrCodeRepository = qrCodeRepository
        self.onSave = onSave

        let existing = alarm ?? Alarm(time: LocalTime(hour: 7, minute: 0))

        var components = DateComponents()
        components.hour = existing.time.hour
        components.minute = existing.time.minute
        _selectedDate = State(initialValue: Calendar.current.date(from: components) ?? Date())

        _label = State(initialValue: existing.label)
        _enabled = State(initialValue: existing.enabled)
        _selectedWeekdays = State(initialValue: existing.recurrence.weekdays)

        _gentleWakeEnabled = State(initialValue: existing.gentleWake.enabled)
        _gentleWakeMinutes = State(initialValue: existing.gentleWake.durationMinutes)

        _snoozeMinutes = State(initialValue: existing.snooze.durationMinutes)
        _snoozeMission = State(initialValue: existing.snooze.mission)
        _unlimitedSnoozes = State(initialValue: existing.snooze.maxSnoozes == nil)
        _maxSnoozes = State(initialValue: existing.snooze.maxSnoozes ?? 3)

        _turnOffMission = State(initialValue: existing.turnOffMission)

        _wakeUpCheckEnabled = State(initialValue: existing.wakeUpCheck.enabled)
        _wakeUpCheckDelayMinutes = State(initialValue: existing.wakeUpCheck.delayMinutes)
        _wakeUpCheckMission = State(initialValue: existing.wakeUpCheck.mission)

        _postAlarmAction = State(initialValue: existing.postAlarmAction)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $selectedDate, displayedComponents: .hourAndMinute)
                    TextField("Label", text: $label)
                    Toggle("Enabled", isOn: $enabled)
                }

                Section("Repeat") {
                    WeekdayPickerRow(selectedWeekdays: $selectedWeekdays)

                    HStack {
                        RecurrencePresetButton(title: "Once", isSelected: selectedWeekdays.isEmpty) {
                            selectedWeekdays = []
                        }
                        RecurrencePresetButton(title: "Weekdays", isSelected: selectedWeekdays == Recurrence.weekdaysOnly.weekdays) {
                            selectedWeekdays = Recurrence.weekdaysOnly.weekdays
                        }
                        RecurrencePresetButton(title: "Weekends", isSelected: selectedWeekdays == Recurrence.weekendsOnly.weekdays) {
                            selectedWeekdays = Recurrence.weekendsOnly.weekdays
                        }
                        RecurrencePresetButton(title: "Every day", isSelected: selectedWeekdays == Recurrence.everyDay.weekdays) {
                            selectedWeekdays = Recurrence.everyDay.weekdays
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Gentle Wake-Up") {
                    Toggle("Wake gently before the alarm", isOn: $gentleWakeEnabled)
                    if gentleWakeEnabled {
                        Stepper("\(gentleWakeMinutes) min before", value: $gentleWakeMinutes, in: 5...30, step: 5)
                    }
                }

                Section("Snooze") {
                    Text("Small movement to help you wake up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper("Snooze for \(snoozeMinutes) min", value: $snoozeMinutes, in: 1...30)
                    Toggle("Unlimited snoozes", isOn: $unlimitedSnoozes)
                    if !unlimitedSnoozes {
                        Stepper("Up to \(maxSnoozes) \(maxSnoozes == 1 ? "snooze" : "snoozes")", value: $maxSnoozes, in: 1...10)
                    }
                }
                MissionConfigurationPicker(
                    title: "Snooze Mission",
                    configuration: $snoozeMission,
                    qrCodeRepository: qrCodeRepository,
                    allowNone: true
                )

                Section("Turn Off") {
                    Text("Get yourself out of bed and start your morning.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                MissionConfigurationPicker(
                    title: "Turn-Off Mission",
                    configuration: $turnOffMission,
                    qrCodeRepository: qrCodeRepository
                )

                Section("Wake-Up Check") {
                    Text("Make sure you're still up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Enable wake-up check", isOn: $wakeUpCheckEnabled)
                    if wakeUpCheckEnabled {
                        Stepper("\(wakeUpCheckDelayMinutes) min after turning off", value: $wakeUpCheckDelayMinutes, in: 5...30, step: 5)
                    }
                }
                if wakeUpCheckEnabled {
                    MissionConfigurationPicker(
                        title: "Wake-Up Check Mission",
                        configuration: $wakeUpCheckMission,
                        qrCodeRepository: qrCodeRepository
                    )
                }

                Section("After You're Up") {
                    Picker("Open app", selection: $postAlarmAction) {
                        ForEach(AppDestination.allCases) { destination in
                            Text(destination.displayName).tag(destination)
                        }
                    }
                }
            }
            .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
        let time = LocalTime(hour: components.hour ?? 7, minute: components.minute ?? 0)

        let savedAlarm = Alarm(
            id: alarm?.id ?? UUID(),
            time: time,
            recurrence: Recurrence(weekdays: selectedWeekdays),
            label: label.isEmpty ? "Alarm" : label,
            enabled: enabled,
            sound: alarm?.sound ?? .default,
            gentleWake: GentleWakeConfiguration(enabled: gentleWakeEnabled, durationMinutes: gentleWakeMinutes),
            snooze: SnoozeConfiguration(
                durationMinutes: snoozeMinutes,
                mission: snoozeMission,
                maxSnoozes: unlimitedSnoozes ? nil : maxSnoozes
            ),
            turnOffMission: turnOffMission,
            wakeUpCheck: WakeUpCheckConfiguration(
                enabled: wakeUpCheckEnabled,
                delayMinutes: wakeUpCheckDelayMinutes,
                mission: wakeUpCheckMission
            ),
            postAlarmAction: postAlarmAction
        )

        onSave(savedAlarm)
        dismiss()
    }
}

private struct WeekdayPickerRow: View {
    @Binding var selectedWeekdays: Set<Weekday>

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { day in
                let isSelected = selectedWeekdays.contains(day)
                Button {
                    if isSelected {
                        selectedWeekdays.remove(day)
                    } else {
                        selectedWeekdays.insert(day)
                    }
                } label: {
                    Text(day.letterSymbol)
                        .font(.subheadline.weight(.medium))
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Color.orange : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct RecurrencePresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(isSelected ? Color.orange : Color.primary)
        }
    }
}

#Preview {
    AlarmEditorView(alarm: nil, qrCodeRepository: FileQRCodeRepository(), onSave: { _ in })
}
