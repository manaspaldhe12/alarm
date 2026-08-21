import SwiftUI

struct QRSetupView: View {
    let repository: QRCodeRepository

    @Environment(\.dismiss) private var dismiss
    @State private var registrations: [QRCodeRegistration] = []
    @State private var isScanning = false
    @State private var pendingContent: String?
    @State private var pendingName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Where should your morning start?")
                        .font(.headline)
                    Text("Put a QR code somewhere you want to go after waking up — the bathroom, kitchen, coffee machine, or front door.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Registered codes") {
                    if registrations.isEmpty {
                        Text("No codes yet").foregroundStyle(.secondary)
                    }
                    ForEach(registrations) { registration in
                        Text(registration.name)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("QR Codes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isScanning = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await reload() }
            .sheet(isPresented: $isScanning) {
                QRRegistrationScanSheet { content in
                    pendingContent = content
                    isScanning = false
                }
            }
            .alert(
                "Name this code",
                isPresented: Binding(
                    get: { pendingContent != nil },
                    set: { isPresented in if !isPresented { pendingContent = nil; pendingName = "" } }
                )
            ) {
                TextField("e.g. Bathroom", text: $pendingName)
                Button("Save") { Task { await save() } }
                Button("Cancel", role: .cancel) { pendingContent = nil; pendingName = "" }
            }
        }
    }

    private func reload() async {
        registrations = (try? await repository.registrations()) ?? []
    }

    private func save() async {
        guard let content = pendingContent, !pendingName.isEmpty else { return }
        _ = try? await repository.register(name: pendingName, rawContent: content)
        pendingContent = nil
        pendingName = ""
        await reload()
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { registrations[$0] }
        Task {
            for registration in toDelete {
                try? await repository.delete(id: registration.id)
            }
            await reload()
        }
    }
}

private struct QRRegistrationScanSheet: View {
    let onScanned: (String) -> Void

    var body: some View {
        ZStack {
            QRScannerView(onDetect: onScanned)
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Scan the QR code you want to register")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
    }
}
