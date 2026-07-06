import CupcakeModels
import CupcakeNetworking
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
    @Query private var labGroups: [CachedLabGroup]
    @Query private var metadataTables: [CachedMetadataTable]
    @Query private var metadataColumns: [CachedMetadataColumn]
    @Query private var jobAnnotations: [CachedInstrumentJobAnnotation]
    @Query private var instrumentUsages: [CachedInstrumentUsage]

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingCreateMetadataSheet = false
    @State private var isShowingBookInstrumentSheet = false
    @State private var isShowingStaffAssignmentSheet = false
    @State private var pendingStaffAssignmentLabGroupServerID: Int64?
    @State private var editingColumn: CachedMetadataColumn?
    @State private var isLoadingBookings = false

    private var job: CachedInstrumentJob? {
        jobs.first(where: { $0.clientID == jobClientID })
    }

    /// Only lab groups with `allowProcessJobs` are offered for job assignment — a deliberate
    /// divergence from the reference web app, which shows every one of the user's lab groups
    /// with no such filter. `allowProcessJobs` only governs whether *new* members automatically
    /// get `can_process_jobs` (the actual per-user permission enforced server-side when staff are
    /// assigned), so this filter is a coarser, intentional narrowing — not a literal mirror of a
    /// server-side eligibility rule for the group itself, which doesn't exist.
    private var jobAssignableLabGroups: [CachedLabGroup] {
        labGroups.filter(\.allowProcessJobs)
    }

    private var projectName: String? {
        guard let projectClientID = job?.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.projectName
    }

    private var metadataTable: CachedMetadataTable? {
        guard let metadataTableServerID = job?.metadataTableServerID else { return nil }
        return metadataTables.first(where: { $0.serverID == metadataTableServerID })
    }

    private var sortedColumns: [CachedMetadataColumn] {
        guard let tableServerID = metadataTable?.serverID else { return [] }
        return metadataColumns
            .filter { $0.metadataTableServerID == tableServerID }
            .sorted { $0.columnPosition < $1.columnPosition }
    }

    private var canSubmit: Bool {
        job?.status == "draft" && job?.serverID != nil
    }

    private var canCancel: Bool {
        guard let status = job?.status, job?.serverID != nil else { return false }
        return status != "completed" && status != "cancelled"
    }

    private var canCreateMetadataTable: Bool {
        job?.serverID != nil && job?.metadataTableServerID == nil
    }

    /// The metadata-merge signal only fires when the job already has a `metadata_table` — see
    /// `InstrumentJobAnnotationSyncService`'s doc comment.
    private var canBookInstrument: Bool {
        job?.serverID != nil && job?.metadataTableServerID != nil
    }

    private var bookingAnnotations: [CachedInstrumentJobAnnotation] {
        jobAnnotations
            .filter { $0.instrumentJobClientID == jobClientID && $0.annotationType == "booking" }
            .sorted { $0.order < $1.order }
    }

    private func instrumentUsage(for annotation: CachedInstrumentJobAnnotation) -> CachedInstrumentUsage? {
        guard let usageServerID = annotation.instrumentUsageServerID else { return nil }
        return instrumentUsages.first(where: { $0.serverID == usageServerID })
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
                if let serverID = job.serverID {
                    Section("Lab Group") {
                        Picker("Lab Group", selection: Binding(
                            get: { job.labGroupServerID },
                            set: { newValue in
                                guard let newValue else { return }
                                Task { await assignLabGroup(jobServerID: serverID, labGroupServerID: newValue) }
                            }
                        )) {
                            Text("None").tag(Int64?.none)
                            ForEach(jobAssignableLabGroups) { group in
                                Text(group.name).tag(Optional(group.serverID))
                            }
                        }
                        .accessibilityIdentifier("jobLabGroupPicker")
                    }
                    if let labGroupServerID = job.labGroupServerID {
                        Section("Staff") {
                            if job.staffUsernames.isEmpty {
                                Text("No staff assigned")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(job.staffUsernames, id: \.self) { username in
                                    Text(username)
                                }
                            }
                            Button("Assign Staff") {
                                pendingStaffAssignmentLabGroupServerID = labGroupServerID
                                isShowingStaffAssignmentSheet = true
                            }
                            .accessibilityIdentifier("assignStaffButton")
                        }
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
                Section("Metadata Table") {
                    if let metadataTable {
                        LabeledContent("Name", value: metadataTable.name)
                        LabeledContent("Samples", value: "\(metadataTable.sampleCount)")
                        ForEach(sortedColumns) { column in
                            Button {
                                editingColumn = column
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(column.displayName ?? column.name)
                                        .foregroundStyle(.primary)
                                    if let value = column.value, !value.isEmpty {
                                        Text(value)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(column.readonly)
                            .accessibilityIdentifier("metadataColumnRow_\(column.name)")
                        }
                    } else {
                        Button("Create from Template") {
                            isShowingCreateMetadataSheet = true
                        }
                        .disabled(!canCreateMetadataTable)
                        .accessibilityIdentifier("createMetadataFromTemplateButton")
                    }
                }
                Section("Bookings") {
                    ForEach(bookingAnnotations) { annotation in
                        VStack(alignment: .leading, spacing: 2) {
                            if let usage = instrumentUsage(for: annotation) {
                                Text(usage.instrumentName)
                                Text(HumanReadableTime.format(usage.timeStarted) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(annotation.annotationText ?? "Booking")
                            }
                        }
                    }
                    if isLoadingBookings {
                        ProgressView()
                    }
                    Button("Book Instrument") {
                        isShowingBookInstrumentSheet = true
                    }
                    .disabled(!canBookInstrument)
                    .accessibilityIdentifier("bookInstrumentForJobButton")
                }
            }
        }
        .navigationTitle(job?.jobName ?? "Job")
        .alert("Couldn't update job", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingCreateMetadataSheet) {
            if let job, let serverID = job.serverID {
                CreateMetadataFromTemplateSheet(jobClientID: job.clientID, jobServerID: serverID, defaultSampleCount: nil)
            }
        }
        .sheet(isPresented: $isShowingBookInstrumentSheet) {
            if let job, let serverID = job.serverID {
                BookInstrumentForJobSheet(jobClientID: job.clientID, jobServerID: serverID)
            }
        }
        .sheet(isPresented: $isShowingStaffAssignmentSheet) {
            if let job, let serverID = job.serverID, let labGroupServerID = pendingStaffAssignmentLabGroupServerID {
                StaffAssignmentSheet(
                    jobClientID: job.clientID,
                    jobServerID: serverID,
                    labGroupServerID: labGroupServerID,
                    initiallySelectedStaffIDs: Set(job.staffServerIDs)
                )
            }
        }
        .sheet(item: $editingColumn) { column in
            MetadataValueEditSheet(column: column)
        }
        .task(id: job?.serverID) {
            await loadBookings()
        }
    }

    private func loadBookings() async {
        guard let serverID = job?.serverID else { return }
        isLoadingBookings = true
        defer { isLoadingBookings = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.instrumentJobAnnotationSync.refetchAnnotations(jobServerID: serverID, jobClientID: jobClientID)
        } catch {
            // Non-fatal — the job detail screen should still render even if the annotation
            // list fails to refresh (e.g. offline); it just shows whatever was last cached.
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
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func assignLabGroup(jobServerID: Int64, labGroupServerID: Int64) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.instrumentJobSync.updateLabGroup(jobServerID: jobServerID, labGroupServerID: labGroupServerID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
