import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct EditProtocolSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let protocolModel: CachedProtocol

    @State private var title: String
    @State private var description: String
    @State private var isPublic: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(protocolModel: CachedProtocol) {
        self.protocolModel = protocolModel
        _title = State(initialValue: protocolModel.protocolTitle)
        _description = State(initialValue: protocolModel.protocolDescription ?? "")
        _isPublic = State(initialValue: protocolModel.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("editProtocolTitleField")
                TextField("Description", text: $description, axis: .vertical)
                    .accessibilityIdentifier("editProtocolDescriptionField")
                Toggle("Public", isOn: $isPublic)
                    .accessibilityIdentifier("editProtocolPublicToggle")
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Protocol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.isEmpty || isSaving)
                    .accessibilityIdentifier("saveEditProtocolButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .alert("Couldn't save protocol", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let serverID = protocolModel.serverID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().protocolSync.update(
                serverID: serverID,
                protocolTitle: title,
                protocolDescription: description.isEmpty ? nil : description,
                enabled: isPublic
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
