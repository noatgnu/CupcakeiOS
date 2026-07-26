import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct NewLabGroupSheet: View {
    var existingGroup: CachedLabGroup?

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var groupDescription: String
    @State private var allowMemberInvites: Bool
    @State private var allowProcessJobs: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existingGroup: CachedLabGroup? = nil) {
        self.existingGroup = existingGroup
        _name = State(initialValue: existingGroup?.name ?? "")
        _groupDescription = State(initialValue: existingGroup?.groupDescription ?? "")
        _allowMemberInvites = State(initialValue: existingGroup?.allowMemberInvites ?? true)
        _allowProcessJobs = State(initialValue: existingGroup?.allowProcessJobs ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("labGroupNameField")
                    TextField("Description (optional)", text: $groupDescription, axis: .vertical)
                        .accessibilityIdentifier("labGroupDescriptionField")
                }
                Section("Settings") {
                    Toggle("Allow Member Invites", isOn: $allowMemberInvites)
                    Toggle("Allow Job Processing", isOn: $allowProcessJobs)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(existingGroup == nil ? "New Lab Group" : "Edit Lab Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .accessibilityIdentifier("saveLabGroupButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existingGroup {
                try await appSession.makeSyncServices().labGroupSync.update(
                    labGroupServerID: existingGroup.serverID,
                    request: UpdateLabGroupRequest(
                        name: name,
                        description: groupDescription.isEmpty ? nil : groupDescription,
                        allowMemberInvites: allowMemberInvites,
                        allowProcessJobs: allowProcessJobs
                    )
                )
            } else {
                try await appSession.makeSyncServices().labGroupSync.create(
                    name: name,
                    description: groupDescription.isEmpty ? nil : groupDescription,
                    parentGroupServerID: nil,
                    allowMemberInvites: allowMemberInvites,
                    allowProcessJobs: allowProcessJobs
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
        }
    }
}
