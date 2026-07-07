import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Sheet for adding a session-scoped step variation. Online-only.
struct AddStepVariationSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let stepServerID: Int64
    let sessionServerID: Int64

    @State private var description = ""
    @State private var durationMinutesText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var durationSeconds: Int? {
        guard let minutes = Int(durationMinutesText) else { return nil }
        return minutes * 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Variation") {
                    TextField("Description", text: $description, axis: .vertical)
                        .accessibilityIdentifier("variationDescriptionField")
                    TextField("Duration (minutes)", text: $durationMinutesText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("variationDurationField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Variation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(description.isEmpty || durationSeconds == nil || isSaving)
                    .accessibilityIdentifier("saveVariationButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)
        .alert("Couldn't add variation", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let durationSeconds else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().stepVariationSync.create(
                stepServerID: stepServerID,
                sessionServerID: sessionServerID,
                variationDescription: description,
                variationDuration: durationSeconds
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
