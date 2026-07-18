import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct EditSessionSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let session: CachedSession

    @State private var name: String
    @State private var isPublic: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(session: CachedSession) {
        self.session = session
        _name = State(initialValue: session.name ?? "")
        _isPublic = State(initialValue: session.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("editSessionNameField")
                Toggle("Public", isOn: $isPublic)
                    .accessibilityIdentifier("editSessionPublicToggle")
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                    .accessibilityIdentifier("saveEditSessionButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
        .alert("Couldn't save session", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let serverID = session.serverID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().sessionSync.update(serverID: serverID, name: name, enabled: isPublic)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
