import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct NewJobSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedProject.createdAt, order: .reverse) private var projects: [CachedProject]

    @State private var jobName = ""
    @State private var jobType = "analysis"
    @State private var selectedProjectID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private static let jobTypeOptions = ["analysis", "maintenance", "other"]

    private var canSave: Bool {
        !jobName.isEmpty
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
                    if projects.isEmpty {
                        Text("No projects yet. Create one from the Projects screen first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
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

        let job = CachedInstrumentJob(jobName: jobName, jobType: jobType, projectClientID: selectedProjectID)
        modelContext.insert(job)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = job.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.instrumentJobSync.syncLocallyCreatedInstrumentJob(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateInstrumentJob(clientID: clientID)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
                isShowingError = true
            }
        } catch SyncDependencyError.parentNotSynced {
            try? await services.outboxSync.enqueueCreateInstrumentJob(clientID: clientID)
            dismiss()
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.userFacingMessage)"
            isShowingError = true
        }
    }
}
