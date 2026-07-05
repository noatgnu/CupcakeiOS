import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

/// `submit`/`cancel` are the only status-transition actions this app exposes, matching what the
/// reference backend's viewset actually wires up (`can_transition_to_status` exists on the
/// model but isn't invoked by any viewset action besides these two) — no generic status picker.
struct JobDetailView: View {
    @Environment(AppSession.self) private var appSession
    let jobClientID: UUID

    @Query private var jobs: [CachedInstrumentJob]
    @Query private var projects: [CachedProject]

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var job: CachedInstrumentJob? {
        jobs.first(where: { $0.clientID == jobClientID })
    }

    private var projectName: String? {
        guard let projectClientID = job?.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.projectName
    }

    private var canSubmit: Bool {
        job?.status == "draft" && job?.serverID != nil
    }

    private var canCancel: Bool {
        guard let status = job?.status, job?.serverID != nil else { return false }
        return status != "completed" && status != "cancelled"
    }

    var body: some View {
        List {
            if let job {
                Section("Info") {
                    LabeledContent("Type", value: job.jobType.capitalized)
                    LabeledContent("Status", value: job.status.capitalized)
                    if let projectName {
                        LabeledContent("Project", value: projectName)
                    }
                    if job.serverID == nil {
                        Text("Pending sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Submit") {
                        Task { await performAction(.submit) }
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .accessibilityIdentifier("submitJobButton")

                    Button("Cancel Job", role: .destructive) {
                        Task { await performAction(.cancel) }
                    }
                    .disabled(!canCancel || isSubmitting)
                    .accessibilityIdentifier("cancelJobButton")
                }
            }
        }
        .navigationTitle(job?.jobName ?? "Job")
        .alert("Couldn't update job", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private enum Action {
        case submit
        case cancel
    }

    private func performAction(_ action: Action) async {
        guard let serverID = job?.serverID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let services = appSession.makeSyncServices()
            switch action {
            case .submit:
                try await services.instrumentJobSync.submit(jobServerID: serverID)
            case .cancel:
                try await services.instrumentJobSync.cancel(jobServerID: serverID)
            }
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}
