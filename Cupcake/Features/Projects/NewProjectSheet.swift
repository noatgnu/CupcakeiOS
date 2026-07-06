import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Matches the reference web app's standalone `ProjectEditModal` — name + description only, its
/// own explicit "New Project" action, not bundled into job creation.
struct NewProjectSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var projectName = ""
    @State private var projectDescription = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $projectName)
                    .accessibilityIdentifier("newProjectNameField")
                TextField("Description", text: $projectDescription)
                    .accessibilityIdentifier("newProjectDescriptionField")
            }
            .formStyle(.grouped)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await save() }
                    }
                    .disabled(projectName.isEmpty || isSaving)
                    .accessibilityIdentifier("createProjectButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
        .alert("Couldn't create project", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let description = projectDescription.isEmpty ? nil : projectDescription
        let project = CachedProject(projectName: projectName, projectDescription: description)
        modelContext.insert(project)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = project.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.projectSync.syncLocallyCreatedProject(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateProject(clientID: clientID)
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
