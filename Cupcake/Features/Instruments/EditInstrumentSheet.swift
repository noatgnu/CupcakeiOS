import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct EditInstrumentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let existingInstrument: CachedInstrument?

    @State private var instrumentName: String
    @State private var instrumentDescription: String
    @State private var enabled: Bool
    @State private var acceptsBookings: Bool
    @State private var allowOverlappingBookings: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(existingInstrument: CachedInstrument? = nil) {
        self.existingInstrument = existingInstrument
        _instrumentName = State(initialValue: existingInstrument?.instrumentName ?? "")
        _instrumentDescription = State(initialValue: existingInstrument?.instrumentDescription ?? "")
        _enabled = State(initialValue: existingInstrument?.enabled ?? true)
        _acceptsBookings = State(initialValue: existingInstrument?.acceptsBookings ?? true)
        _allowOverlappingBookings = State(initialValue: existingInstrument?.allowOverlappingBookings ?? false)
    }

    private var isEditing: Bool { existingInstrument != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $instrumentName)
                    .accessibilityIdentifier("instrumentNameField")
                TextField("Description", text: $instrumentDescription, axis: .vertical)
                    .accessibilityIdentifier("instrumentDescriptionField")
                Toggle("Enabled", isOn: $enabled)
                    .accessibilityIdentifier("instrumentEnabledToggle")
                Toggle("Accepts Bookings", isOn: $acceptsBookings)
                    .accessibilityIdentifier("instrumentAcceptsBookingsToggle")
                if acceptsBookings {
                    Toggle("Allow Overlapping Bookings", isOn: $allowOverlappingBookings)
                        .accessibilityIdentifier("instrumentAllowOverlappingBookingsToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Instrument" : "New Instrument")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .disabled(instrumentName.isEmpty || isSaving)
                    .accessibilityIdentifier("saveInstrumentButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .alert(isEditing ? "Couldn't save instrument" : "Couldn't create instrument", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let description = instrumentDescription.isEmpty ? nil : instrumentDescription
        do {
            if let existingInstrument {
                try await appSession.makeSyncServices().instrumentSync.updateInstrument(
                    serverID: existingInstrument.serverID,
                    instrumentName: instrumentName,
                    instrumentDescription: description,
                    enabled: enabled,
                    acceptsBookings: acceptsBookings,
                    allowOverlappingBookings: allowOverlappingBookings
                )
            } else {
                try await appSession.makeSyncServices().instrumentSync.createInstrument(
                    instrumentName: instrumentName,
                    instrumentDescription: description,
                    enabled: enabled,
                    acceptsBookings: acceptsBookings,
                    allowOverlappingBookings: allowOverlappingBookings
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
