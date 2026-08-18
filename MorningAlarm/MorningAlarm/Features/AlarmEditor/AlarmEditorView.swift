import SwiftUI

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let alarm: Alarm?
    let onSave: (Alarm) -> Void

    @State private var selectedDate: Date
    @State private var label: String
    @State private var enabled: Bool

    init(alarm: Alarm?, onSave: @escaping (Alarm) -> Void) {
        self.alarm = alarm
        self.onSave = onSave

        if let alarm {
            var components = DateComponents()
            components.hour = alarm.time.hour
            components.minute = alarm.time.minute
            let date = Calendar.current.date(from: components) ?? Date()
            _selectedDate = State(initialValue: date)
            _label = State(initialValue: alarm.label)
            _enabled = State(initialValue: alarm.enabled)
        } else {
            _selectedDate = State(initialValue: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date())
            _label = State(initialValue: "Alarm")
            _enabled = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $selectedDate, displayedComponents: .hourAndMinute)

                TextField("Label", text: $label)

                Toggle("Enabled", isOn: $enabled)
            }
            .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
                        let time = LocalTime(
                            hour: components.hour ?? 7,
                            minute: components.minute ?? 0
                        )

                        let savedAlarm = Alarm(
                            id: alarm?.id ?? UUID(),
                            time: time,
                            label: label.isEmpty ? "Alarm" : label,
                            enabled: enabled,
                            sound: alarm?.sound ?? .default,
                            snooze: alarm?.snooze ?? .default
                        )

                        onSave(savedAlarm)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    AlarmEditorView(alarm: nil, onSave: { _ in })
}
