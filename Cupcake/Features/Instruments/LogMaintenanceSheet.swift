import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Creates a maintenance log for an instrument. Online-only.
struct LogMaintenanceSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let instrumentServerID: Int64
    let instrumentName: String

    private static let types: [(value: String, label: String)] = [
        ("routine", "Routine"), ("emergency", "Emergency"), ("other", "Other"),
    ]
    private static let statuses: [(value: String, label: String)] = [
        ("pending", "Pending"), ("in_progress", "In Progress"), ("completed", "Completed"),
        ("requested", "Requested"), ("cancelled", "Cancelled"),
    ]

    @State private var maintenanceDate = Date()
    @State private var maintenanceType = "routine"
    @State private var status = "pending"
    @State private var maintenanceDescription = ""
    @State private var maintenanceNotes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $maintenanceDate)
                        .accessibilityIdentifier("maintenanceDatePicker")
                    Picker("Type", selection: $maintenanceType) {
                        ForEach(Self.types, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("maintenanceTypePicker")
                    Picker("Status", selection: $status) {
                        ForEach(Self.statuses, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .accessibilityIdentifier("maintenanceStatusPicker")
                    TextField("Description", text: $maintenanceDescription, axis: .vertical)
                        .accessibilityIdentifier("maintenanceDescriptionField")
                    TextField("Notes", text: $maintenanceNotes, axis: .vertical)
                        .accessibilityIdentifier("maintenanceNotesField")
                } footer: {
                    Text("Logging maintenance for \(instrumentName).")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log Maintenance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveMaintenanceLogButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 440)
        .alert("Couldn't log maintenance", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().maintenanceLogSync.create(
                instrumentServerID: instrumentServerID,
                maintenanceDate: Self.iso8601.string(from: maintenanceDate),
                maintenanceType: maintenanceType,
                status: status,
                maintenanceDescription: maintenanceDescription.isEmpty ? nil : maintenanceDescription,
                maintenanceNotes: maintenanceNotes.isEmpty ? nil : maintenanceNotes
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
}
