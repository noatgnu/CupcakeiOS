import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct NewProtocolView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var description = ""
    @State private var enabled = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Protocol") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("newProtocolTitleField")
                    TextField("Description", text: $description, axis: .vertical)
                        .accessibilityIdentifier("newProtocolDescriptionField")
                    Toggle("Public", isOn: $enabled)
                        .accessibilityIdentifier("newProtocolEnabledToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Protocol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createProtocol() }
                    }
                    .disabled(title.isEmpty || isCreating)
                    .accessibilityIdentifier("createProtocolButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 260)
        .alert("Couldn't create protocol", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createProtocol() async {
        isCreating = true
        defer { isCreating = false }

        let protocolModel = CachedProtocol(
            protocolTitle: title,
            protocolDescription: description,
            enabled: enabled,
            isLocallyAuthored: true
        )
        modelContext.insert(protocolModel)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = protocolModel.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.protocolSync.syncLocallyCreatedProtocol(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateProtocol(clientID: clientID, title: title, description: description, enabled: enabled)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }
}
