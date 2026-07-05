import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Matches the reference web app's `job-submission.ts` step 1 exactly — the only fields
/// collected at creation time are job name/type and a project (either an existing one or a
/// brand-new one created inline); every other field (lab group, staff, samples, template) is a
/// separate `PATCH` after the job already exists as a draft, not part of this app's v1 slice at
/// all yet (see the plan's Phase 4.5 deferred list).
///
/// Always created locally first, then synced immediately when signed in — a genuine
/// unreachability failure queues it in the outbox, same pattern as every other create flow.
struct NewJobSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedProject.projectName) private var projects: [CachedProject]

    @State private var jobName = ""
    @State private var jobType = "analysis"
    @State private var selectedProjectID: UUID?
    @State private var isCreatingNewProject = false
    @State private var newProjectName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private static let jobTypeOptions = ["analysis", "maintenance", "other"]

    private var canSave: Bool {
        guard !jobName.isEmpty else { return false }
        if isCreatingNewProject { return !newProjectName.isEmpty }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Job name", text: $jobName)
                        .accessibilityIdentifier("newJobNameField")
                    Picker("Type", selection: $jobType) {
                        ForEach(Self.jobTypeOptions, id: \.self) { option in
                            Text(option.capitalized).tag(option)
                        }
                    }
                    .accessibilityIdentifier("newJobTypePicker")
                }
                Section("Project") {
                    Toggle("Create new project", isOn: $isCreatingNewProject)
                        .accessibilityIdentifier("newJobCreateProjectToggle")
                    if isCreatingNewProject {
                        TextField("Project name", text: $newProjectName)
                            .accessibilityIdentifier("newJobNewProjectNameField")
                    } else if !projects.isEmpty {
                        Picker("Project", selection: $selectedProjectID) {
                            Text("None").tag(UUID?.none)
                            ForEach(projects) { project in
                                Text(project.projectName).tag(Optional(project.clientID))
                            }
                        }
                        .accessibilityIdentifier("newJobExistingProjectPicker")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("createJobButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 340)
        .alert("Couldn't create job", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let services = appSession.makeSyncServices()

        var projectClientID: UUID?
        if isCreatingNewProject {
            let project = CachedProject(projectName: newProjectName)
            modelContext.insert(project)
            try? modelContext.save()
            projectClientID = project.clientID
            if appSession.isAuthenticated {
                await syncOrQueueProject(project.clientID, services: services)
            }
        } else {
            projectClientID = selectedProjectID
        }

        let job = CachedInstrumentJob(jobName: jobName, jobType: jobType, projectClientID: projectClientID)
        modelContext.insert(job)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = job.clientID
        do {
            try await services.instrumentJobSync.syncLocallyCreatedInstrumentJob(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateInstrumentJob(clientID: clientID)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateInstrumentJob(clientID: clientID)
            dismiss()
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private func syncOrQueueProject(_ clientID: UUID, services: SyncServices) async {
        do {
            try await services.projectSync.syncLocallyCreatedProject(clientID: clientID)
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateProject(clientID: clientID)
            }
        } catch {
            // A non-transport project-sync failure shouldn't block job creation — the job still
            // gets created locally either way, and the project stays queued for a manual retry
            // via Sync Issues.
        }
    }
}
