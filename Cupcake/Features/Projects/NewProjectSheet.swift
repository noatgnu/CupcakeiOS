import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct NewProjectSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let existingProject: CachedProject?

    @State private var projectName: String
    @State private var projectDescription: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(existingProject: CachedProject? = nil) {
        self.existingProject = existingProject
        _projectName = State(initialValue: existingProject?.projectName ?? "")
        _projectDescription = State(initialValue: existingProject?.projectDescription ?? "")
    }

    private var isEditing: Bool { existingProject != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $projectName)
                    .accessibilityIdentifier("newProjectNameField")
                TextField("Description", text: $projectDescription)
                    .accessibilityIdentifier("newProjectDescriptionField")
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Project" : "New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .disabled(projectName.isEmpty || isSaving)
                    .accessibilityIdentifier("createProjectButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 220)
        .alert(isEditing ? "Couldn't save project" : "Couldn't create project", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        if let existingProject {
            await update(existingProject)
        } else {
            await create()
        }
    }

    private func update(_ project: CachedProject) async {
        guard let serverID = project.serverID else { return }
        isSaving = true
        defer { isSaving = false }
        let description = projectDescription.isEmpty ? nil : projectDescription
        do {
            try await appSession.makeSyncServices().projectSync.update(serverID: serverID, projectName: projectName, projectDescription: description)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func create() async {
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
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }
}
