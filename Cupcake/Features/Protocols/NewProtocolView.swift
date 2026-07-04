import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Matches the reference web app's own creation flow exactly (`protocol-create-modal.ts`):
/// title, description, and an "enabled" checkbox (public/accessible-to-everyone — defaults to
/// `false`, matching the web form's own default and the Django serializer's default) are the
/// only fields; no section or step is created alongside it. Content always gets added
/// afterward, and always in that order — a section must exist before a step can be added to it
/// (`ProtocolDetailView`'s "Add Section" then "Add Step" — there is no path that creates a step
/// without an owning section).
///
/// When signed in, the protocol is created **locally first** — so nothing is lost or blocked on
/// the network — then synced to the server immediately. If that sync fails because the server
/// is genuinely unreachable (`APIError.transport`), the sync is queued in the outbox for later
/// automatic retry (`OutboxService`) instead of just erroring out. A real server-side rejection
/// (`APIError.http` — an actual validation/auth problem) surfaces immediately instead, since
/// retrying it later would never succeed. In standalone mode, it's local-only forever, with no
/// outbox entry at all.
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
                errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
                isShowingError = true
            }
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
            isShowingError = true
        }
    }
}
