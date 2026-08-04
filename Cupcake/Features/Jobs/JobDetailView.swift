import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct JobDetailWindowID: Codable, Hashable {
    let namespaceID: UUID
    let jobClientID: UUID
}

struct JobDetailWindowContent: View {
    let windowID: JobDetailWindowID?
    let ontologyStore: ModelContainer

    var body: some View {
        if let windowID {
            NavigationStack {
                JobDetailView(jobClientID: windowID.jobClientID, ontologyStore: ontologyStore)
            }
        } else {
            ContentUnavailableView("Job Not Found", systemImage: "questionmark.square.dashed")
        }
    }
}

struct JobDetailView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.namespaceID) private var namespaceID
    let jobClientID: UUID
    let ontologyStore: ModelContainer

    @Query private var jobs: [CachedInstrumentJob]
    @Query private var projects: [CachedProject]
    @Query private var labGroups: [CachedLabGroup]
    @Query private var metadataTables: [CachedMetadataTable]
    @Query private var metadataColumns: [CachedMetadataColumn]
    @Query private var jobAnnotations: [CachedInstrumentJobAnnotation]
    @Query private var instrumentUsages: [CachedInstrumentUsage]
    @Query private var samplePools: [CachedSamplePool]

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingCreateMetadataSheet = false
    @State private var isShowingNewTemplateSheet = false
    @State private var isShowingBookInstrumentSheet = false
    @State private var isShowingStaffAssignmentSheet = false
    @State private var editingCell: MetadataCellEditTarget?
    @State private var isLoadingBookings = false
    @State private var isShowingAddColumnSheet = false
    @State private var columnSettingsTarget: CachedMetadataColumn?
    @State private var isShowingFullTableView = false
    @State private var isShowingNewSamplePoolSheet = false
    @State private var editingSamplePool: CachedSamplePool?
    @State private var staffOnlyFilter: StaffOnlyFilter = .all
    @State private var columnSearchText = ""
    @State private var isGridPreviewExpanded = true
    @State private var funderText = ""
    @State private var labGroupSearchText = ""
    @State private var isChangingLabGroup = false
    @State private var costCenterText = ""
    @State private var isSavingJobDetails = false

    private enum StaffOnlyFilter: String, CaseIterable {
        case all = "All"
        case user = "User"
        case staff = "Staff"
    }

    private var job: CachedInstrumentJob? {
        jobs.first(where: { $0.clientID == jobClientID })
    }

    private var jobAssignableLabGroups: [CachedLabGroup] {
        labGroups.filter(\.allowProcessJobs)
    }

    private var filteredAssignableLabGroups: [CachedLabGroup] {
        guard !labGroupSearchText.isEmpty else { return jobAssignableLabGroups }
        return jobAssignableLabGroups.filter { $0.name.localizedCaseInsensitiveContains(labGroupSearchText) }
    }

    private var projectName: String? {
        guard let projectClientID = job?.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.projectName
    }

    private var projectServerID: Int64? {
        guard let projectClientID = job?.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.serverID
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

    private var filteredColumns: [CachedMetadataColumn] {
        let staffFiltered: [CachedMetadataColumn]
        switch staffOnlyFilter {
        case .all: staffFiltered = sortedColumns
        case .user: staffFiltered = sortedColumns.filter { !$0.staffOnly }
        case .staff: staffFiltered = sortedColumns.filter { $0.staffOnly }
        }
        guard !columnSearchText.isEmpty else { return staffFiltered }
        return staffFiltered.filter { ($0.displayName ?? $0.name).localizedCaseInsensitiveContains(columnSearchText) }
    }

    private var canEditStaffOnlyColumns: Bool {
        job?.canEditStaffOnlyColumns ?? false
    }

    private func canEditCell(_ column: CachedMetadataColumn) -> Bool {
        guard let metadataTable, metadataTable.canEdit, !column.readonly else { return false }
        return !column.staffOnly || canEditStaffOnlyColumns
    }

    private func resolvedValue(column: CachedMetadataColumn, sampleIndex: Int) -> String {
        if let modifier = column.modifiers.first(where: { SampleIndexTextParser.parse($0.samples).contains(sampleIndex) }) {
            return modifier.value
        }
        return column.value ?? ""
    }

    private var sortedSamplePools: [CachedSamplePool] {
        guard let tableServerID = metadataTable?.serverID else { return [] }
        return samplePools
            .filter { $0.metadataTableServerID == tableServerID }
            .sorted { $0.poolName < $1.poolName }
    }

    private var canSubmit: Bool {
        job?.status == "draft" && job?.serverID != nil
    }

    private var canCancel: Bool {
        guard let status = job?.status, job?.serverID != nil else { return false }
        return status != "completed" && status != "cancelled"
    }

    private var canCreateMetadataTable: Bool {
        job?.serverID != nil && job?.metadataTableServerID == nil && job?.labGroupServerID != nil
    }

    private var canBookInstrument: Bool {
        guard job?.serverID != nil, job?.metadataTableServerID != nil, let labGroupServerID = job?.labGroupServerID else {
            return false
        }
        return labGroups.contains(where: { $0.serverID == labGroupServerID })
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
                    Section("Funding") {
                        TextField("Funder", text: $funderText)
                            .accessibilityIdentifier("jobFunderField")
                        TextField("Cost Center", text: $costCenterText)
                            .accessibilityIdentifier("jobCostCenterField")
                        Button("Save Details") {
                            Task { await saveJobDetails(job: job, jobServerID: serverID) }
                        }
                        .disabled(isSavingJobDetails || (funderText == (job.funder ?? "") && costCenterText == (job.costCenter ?? "")))
                        .accessibilityIdentifier("saveJobDetailsButton")
                    }
                    Section("Lab Group") {
                        if let currentName = jobAssignableLabGroups.first(where: { $0.serverID == job.labGroupServerID })?.name, !isChangingLabGroup {
                            HStack {
                                Text(currentName)
                                Spacer()
                                Button("Change") { isChangingLabGroup = true }
                                    .accessibilityIdentifier("changeLabGroupButton")
                            }
                        } else {
                            TextField("Search lab groups", text: $labGroupSearchText)
                                .accessibilityIdentifier("jobLabGroupSearchField")
                            ForEach(filteredAssignableLabGroups) { group in
                                Button {
                                    Task { await assignLabGroup(jobServerID: serverID, labGroupServerID: group.serverID) }
                                    isChangingLabGroup = false
                                } label: {
                                    HStack {
                                        Text(group.name)
                                        Spacer()
                                        if job.labGroupServerID == group.serverID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                .accessibilityIdentifier("jobLabGroupRow_\(group.name)")
                            }
                        }
                    }
                    if job.labGroupServerID != nil {
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
                        Button {
                            openFullTableView(metadataTable: metadataTable)
                        } label: {
                            Label("Open Full Table View", systemImage: "tablecells")
                        }
                        .accessibilityIdentifier("openFullMetadataTableViewButton")
                        if sortedColumns.count > 5 {
                            TextField("Search columns", text: $columnSearchText)
                                .accessibilityIdentifier("jobMetadataColumnSearchField")
                        }
                        if sortedColumns.contains(where: \.staffOnly) {
                            Picker("Show", selection: $staffOnlyFilter) {
                                ForEach(StaffOnlyFilter.allCases, id: \.self) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("staffOnlyFilterPicker")
                        }
                        ForEach(filteredColumns) { column in
                            Button {
                                openCellEditor(column: column, sampleIndex: nil)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(column.displayName ?? column.name)
                                            .foregroundStyle(.primary)
                                        if column.staffOnly {
                                            Image(systemName: "lock.shield")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                                .accessibilityIdentifier("staffOnlyBadge_\(column.name)")
                                        }
                                        if column.mandatory {
                                            Image(systemName: "asterisk")
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                        }
                                        if column.readonly {
                                            Image(systemName: "lock")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    if let value = column.value, !value.isEmpty {
                                        Text(value)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEditCell(column))
                            .accessibilityIdentifier("metadataColumnRow_\(column.name)")
                            .swipeActions(edge: .leading) {
                                Button {
                                    columnSettingsTarget = column
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                                .tint(.gray)
                                .accessibilityIdentifier("columnSettingsButton_\(column.name)")
                            }
                            .contextMenu {
                                Button {
                                    columnSettingsTarget = column
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                                .accessibilityIdentifier("columnSettingsMenuButton_\(column.name)")
                            }
                        }
                        .onDelete { offsets in
                            Task { await removeColumns(at: offsets) }
                        }
                        if metadataTable.canEdit {
                            Button("Add Column") {
                                isShowingAddColumnSheet = true
                            }
                            .accessibilityIdentifier("addMetadataColumnButton")
                        }
                        if metadataTable.sampleCount > 0, !filteredColumns.isEmpty {
                            DisclosureGroup("Sample Grid Preview", isExpanded: $isGridPreviewExpanded) {
                                metadataGrid(sampleCount: metadataTable.sampleCount)
                            }
                            .accessibilityIdentifier("metadataGridPreviewDisclosure")
                        }
                    } else {
                        Button("Create from Template") {
                            isShowingCreateMetadataSheet = true
                        }
                        .disabled(!canCreateMetadataTable)
                        .accessibilityIdentifier("createMetadataFromTemplateButton")
                    }
                }
                if let metadataTable {
                    Section("Sample Pools") {
                        ForEach(sortedSamplePools) { pool in
                            Button {
                                editingSamplePool = pool
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(pool.poolName)
                                            .foregroundStyle(.primary)
                                        if pool.isReference {
                                            Text("· Reference")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text("\(pool.totalSamples) sample(s)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("samplePoolRow_\(pool.poolName)")
                        }
                        .onDelete { offsets in
                            Task { await deleteSamplePools(at: offsets) }
                        }
                        Button("New Sample Pool") {
                            isShowingNewSamplePoolSheet = true
                        }
                        .disabled(metadataTable.sampleCount < 1)
                        .accessibilityIdentifier("newSamplePoolButton")
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
        .toolbar {
            if PlatformWindowPreference.prefersSeparateWindow {
                ToolbarItem {
                    Button {
                        openWindow(id: "job-detail-window", value: JobDetailWindowID(namespaceID: namespaceID, jobClientID: jobClientID))
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                    .accessibilityIdentifier("openJobInWindowButton")
                }
            }
        }
        .alert("Couldn't update job", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingCreateMetadataSheet) {
            if let job, let serverID = job.serverID {
                CreateMetadataFromTemplateSheet(
                    jobClientID: job.clientID,
                    jobServerID: serverID,
                    jobLabGroupServerID: job.labGroupServerID,
                    defaultSampleCount: nil
                ) { tableServerID in
                    job.metadataTableServerID = tableServerID
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $isShowingBookInstrumentSheet) {
            if let job, let serverID = job.serverID {
                BookInstrumentForJobSheet(jobClientID: job.clientID, jobServerID: serverID)
            }
        }
        .sheet(isPresented: $isShowingStaffAssignmentSheet) {
            if let job, let serverID = job.serverID, let labGroupServerID = job.labGroupServerID {
                StaffAssignmentSheet(
                    jobClientID: job.clientID,
                    jobServerID: serverID,
                    labGroupServerID: labGroupServerID,
                    initiallySelectedStaffIDs: Set(job.staffServerIDs)
                )
            }
        }
        .sheet(item: $editingCell) { target in
            MetadataValueEditSheet(column: target.column, sampleIndex: target.sampleIndex, projectServerID: projectServerID, ontologyStore: ontologyStore)
        }
        .sheet(isPresented: $isShowingAddColumnSheet) {
            if let tableServerID = metadataTable?.serverID {
                AddMetadataColumnSheet(tableServerID: tableServerID, ontologyStore: ontologyStore) {
                    await refreshMetadataTable()
                }
            }
        }
        .sheet(item: $columnSettingsTarget) { column in
            MetadataColumnSettingsSheet(column: column.asDTO) { _ in
                await refreshMetadataTable()
            }
        }
        .sheet(isPresented: $isShowingFullTableView) {
            if let metadataTable {
                NavigationStack {
                    MetadataTableDetailView(
                        metadataTableServerID: metadataTable.serverID,
                        sampleCount: metadataTable.sampleCount,
                        canEdit: metadataTable.canEdit,
                        projectServerID: projectServerID,
                        ontologyStore: ontologyStore
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isShowingFullTableView = false }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingNewSamplePoolSheet) {
            if let metadataTable {
                SamplePoolEditSheet(metadataTableServerID: metadataTable.serverID, sampleCount: metadataTable.sampleCount)
            }
        }
        .sheet(item: $editingSamplePool) { pool in
            SamplePoolEditSheet(metadataTableServerID: pool.metadataTableServerID, sampleCount: metadataTable?.sampleCount ?? 0, existingPool: pool)
        }
        .task(id: job?.serverID) {
            await loadBookings()
            if job?.serverID != nil, metadataTable == nil {
                await refreshMetadataTable()
            }
        }
        .task(id: metadataTable?.serverID) {
            await refreshSamplePools()
        }
        .task(id: job?.clientID) {
            funderText = job?.funder ?? ""
            costCenterText = job?.costCenter ?? ""
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
        }
    }

    private func refreshMetadataTable() async {
        guard let serverID = job?.serverID else { return }
        _ = try? await appSession.makeSyncServices().instrumentJobSync.refreshMetadataTable(jobServerID: serverID, jobClientID: jobClientID)
    }

    private func refreshSamplePools() async {
        guard let tableServerID = metadataTable?.serverID else { return }
        try? await appSession.makeSyncServices().samplePoolSync.refetch(metadataTableServerID: tableServerID)
    }

    private func deleteSamplePools(at offsets: IndexSet) async {
        let poolsToRemove = offsets.map { sortedSamplePools[$0] }
        do {
            let services = appSession.makeSyncServices()
            for pool in poolsToRemove {
                try await services.samplePoolSync.delete(serverID: pool.serverID)
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func openCellEditor(column: CachedMetadataColumn, sampleIndex: Int?) {
        if PlatformWindowPreference.prefersSeparateWindow {
            openWindow(id: "metadata-value-editor", value: MetadataValueEditWindowID(namespaceID: namespaceID, columnServerID: column.serverID, sampleIndex: sampleIndex, projectServerID: projectServerID))
        } else {
            editingCell = MetadataCellEditTarget(column: column, sampleIndex: sampleIndex)
        }
    }

    private func openFullTableView(metadataTable: CachedMetadataTable) {
        if PlatformWindowPreference.prefersSeparateWindow {
            openWindow(id: "metadata-table-detail", value: MetadataTableDetailWindowID(namespaceID: namespaceID, metadataTableServerID: metadataTable.serverID, jobClientID: jobClientID, projectServerID: projectServerID))
        } else {
            isShowingFullTableView = true
        }
    }

    @ViewBuilder
    private func metadataGrid(sampleCount: Int) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Sample")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(filteredColumns) { column in
                        Text(column.displayName ?? column.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(1...sampleCount, id: \.self) { sampleIndex in
                    GridRow {
                        Text("\(sampleIndex)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(filteredColumns) { column in
                            let cellValue = resolvedValue(column: column, sampleIndex: sampleIndex)
                            Button {
                                openCellEditor(column: column, sampleIndex: sampleIndex)
                            } label: {
                                Text(cellValue.isEmpty ? "-" : cellValue)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(minWidth: 80, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canEditCell(column))
                            .accessibilityIdentifier("metadataCell_\(column.name)_\(sampleIndex)")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func removeColumns(at offsets: IndexSet) async {
        guard let tableServerID = metadataTable?.serverID else { return }
        let columnsToRemove = offsets.map { filteredColumns[$0] }
        do {
            let services = appSession.makeSyncServices()
            for column in columnsToRemove {
                try await services.metadataColumnSync.removeColumn(tableServerID: tableServerID, columnServerID: column.serverID)
            }
            await refreshMetadataTable()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
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
            _ = try await services.instrumentJobSync.updateLabGroup(jobServerID: jobServerID, labGroupServerID: labGroupServerID)
            job?.labGroupServerID = labGroupServerID
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func saveJobDetails(job: CachedInstrumentJob, jobServerID: Int64) async {
        isSavingJobDetails = true
        defer { isSavingJobDetails = false }
        let funder = funderText.isEmpty ? nil : funderText
        let costCenter = costCenterText.isEmpty ? nil : costCenterText
        do {
            let services = appSession.makeSyncServices()
            try await services.instrumentJobSync.updateFunderCostCenter(jobServerID: jobServerID, funder: funder, costCenter: costCenter)
            job.funder = funder
            job.costCenter = costCenter
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

extension CachedMetadataColumn {
    var asDTO: MetadataColumnDTO {
        MetadataColumnDTO(
            id: serverID,
            name: name,
            displayName: displayName,
            type: type,
            columnPosition: columnPosition,
            value: value,
            notApplicable: notApplicable,
            notAvailable: notAvailable,
            mandatory: mandatory,
            hidden: hidden,
            readonly: readonly,
            ontologyType: ontologyType,
            staffOnly: staffOnly,
            modifiers: []
        )
    }
}
