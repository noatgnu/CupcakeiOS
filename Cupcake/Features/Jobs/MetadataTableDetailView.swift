import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MetadataTableDetailWindowID: Codable, Hashable {
    let namespaceID: UUID
    let metadataTableServerID: Int64
    let jobClientID: UUID?
    let projectServerID: Int64?
}

struct MetadataTableDetailWindowContent: View {
    let windowID: MetadataTableDetailWindowID?
    let ontologyStore: ModelContainer

    @Query private var metadataTables: [CachedMetadataTable]

    private var table: CachedMetadataTable? {
        guard let windowID else { return nil }
        return metadataTables.first { $0.serverID == windowID.metadataTableServerID }
    }

    var body: some View {
        if let windowID, let table {
            NavigationStack {
                MetadataTableDetailView(
                    metadataTableServerID: windowID.metadataTableServerID,
                    sampleCount: table.sampleCount,
                    canEdit: table.canEdit,
                    projectServerID: windowID.projectServerID,
                    ontologyStore: ontologyStore
                )
            }
        } else {
            ContentUnavailableView("Metadata Table Not Found", systemImage: "tablecells")
        }
    }
}

struct MetadataTableDetailView: View {
    let metadataTableServerID: Int64
    let sampleCount: Int
    let canEdit: Bool
    let projectServerID: Int64?
    let ontologyStore: ModelContainer

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.namespaceID) private var namespaceID
    @Query private var allColumns: [CachedMetadataColumn]

    private enum ViewMode: String, CaseIterable, Identifiable {
        case list = "List"
        case table = "Table"
        var id: String { rawValue }
    }

    private static let pageSizes = [10, 25, 50, 100]

    @State private var viewMode: ViewMode = .table
    @State private var columnFilter = ""
    @State private var pageSize = 10
    @State private var currentPage = 1
    @State private var samplePools: [SamplePoolDTO] = []
    @State private var isLoadingPools = false
    @State private var editingCell: MetadataCellEditTarget?
    @State private var columnSettingsTarget: CachedMetadataColumn?
    @State private var autofillTarget: CachedMetadataColumn?
    @State private var findReplaceTarget: CachedMetadataColumn?
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isExportingSDRF = false
    @State private var isExportingExcel = false
    @State private var isShowingAsyncTaskCenter = false
    @State private var exportedTaskMessage: String?
    @State private var isShowingExportedTaskMessage = false
    @State private var isShowingImportPicker = false
    @State private var isImporting = false
    @State private var replaceExistingOnImport = false
    @State private var importScope: AsyncMetadataImportScope = .userMetadata
    @State private var pendingAsyncTaskCount = 0

    private var allTableColumns: [CachedMetadataColumn] {
        allColumns
            .filter { $0.metadataTableServerID == metadataTableServerID }
            .sorted { $0.columnPosition < $1.columnPosition }
    }

    private var columns: [CachedMetadataColumn] {
        allTableColumns
            .filter { columnFilter.isEmpty || ($0.displayName ?? $0.name).localizedCaseInsensitiveContains(columnFilter) }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(sampleCount) / Double(pageSize))))
    }

    private var pageSampleIndices: [Int] {
        let start = (currentPage - 1) * pageSize + 1
        let end = min(start + pageSize - 1, sampleCount)
        guard start <= end else { return [] }
        return Array(start...end)
    }

    private func resolvedValue(column: CachedMetadataColumn, sampleIndex: Int) -> String {
        if let modifier = column.modifiers.first(where: { SampleIndexTextParser.parse($0.samples).contains(sampleIndex) }) {
            return modifier.value
        }
        return column.value ?? ""
    }

    private func canEditCell(_ column: CachedMetadataColumn) -> Bool {
        canEdit && !column.readonly
    }

    var body: some View {
        Form {
            Section {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("metadataTableViewModePicker")
                TextField("Filter columns", text: $columnFilter)
                    .accessibilityIdentifier("metadataTableColumnFilterField")
            }
            if viewMode == .list {
                listModeContent
            } else {
                tableModeContent
            }
            if !samplePools.isEmpty {
                samplePoolsSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Metadata Table")
        .overlay(alignment: .topLeading) {
            Text("\(pendingAsyncTaskCount)")
                .accessibilityIdentifier("pendingAsyncTaskCount")
                .frame(width: 0, height: 0)
                .clipped()
                .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        Task { await submitExport(format: .sdrf) }
                    } label: {
                        if isExportingSDRF {
                            ProgressView()
                        } else {
                            Text("Export as SDRF")
                        }
                    }
                    .accessibilityIdentifier("exportSDRFButton")
                    .disabled(allTableColumns.isEmpty || isExportingSDRF || isExportingExcel)
                    Button {
                        Task { await submitExport(format: .excel) }
                    } label: {
                        if isExportingExcel {
                            ProgressView()
                        } else {
                            Text("Export as Excel")
                        }
                    }
                    .accessibilityIdentifier("exportExcelButton")
                    .disabled(allTableColumns.isEmpty || isExportingSDRF || isExportingExcel)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("exportMenu")
                .help("Export Table")
            }
            if canEdit {
                ToolbarItem {
                    Menu {
                        Toggle("Replace Existing Data", isOn: $replaceExistingOnImport)
                            .accessibilityIdentifier("importReplaceExistingToggle")
                        if appSession.isStaff {
                            Picker("Columns to Import", selection: $importScope) {
                                ForEach(AsyncMetadataImportScope.allCases, id: \.self) { scope in
                                    Text(scope.displayName).tag(scope)
                                }
                            }
                            .accessibilityIdentifier("importScopePicker")
                        }
                        Button {
                            isShowingImportPicker = true
                        } label: {
                            if isImporting {
                                ProgressView()
                            } else {
                                Text("Choose SDRF File…")
                            }
                        }
                        .accessibilityIdentifier("importSDRFButton")
                        .disabled(isImporting)
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importMenu")
                    .help("Import Table")
                }
            }
            ToolbarItem {
                Button {
                    if PlatformWindowPreference.prefersSeparateWindow {
                        PlatformWindowPreference.openOrFocusWindow(id: "async-task-center", namespaceID: namespaceID, using: openWindow)
                    } else {
                        isShowingAsyncTaskCenter = true
                    }
                } label: {
                    Label(
                        pendingAsyncTaskCount == 0 ? "Async Tasks" : "Async Tasks (\(pendingAsyncTaskCount))",
                        systemImage: pendingAsyncTaskCount == 0 ? "clock.arrow.circlepath" : "clock.badge.exclamationmark"
                    )
                }
                .accessibilityIdentifier("openAsyncTaskCenterButton")
                .help("Async Tasks")
            }
        }
        .alert("Couldn't load sample pools", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Export Queued", isPresented: $isShowingExportedTaskMessage) {
            Button("OK") {}
        } message: {
            Text(exportedTaskMessage ?? "")
        }
        .sheet(isPresented: $isShowingAsyncTaskCenter) {
            NavigationStack {
                AsyncTaskCenterView()
            }
        }
        .onChange(of: isShowingAsyncTaskCenter) { _, isShowing in
            if !isShowing {
                Task { await refreshAsyncTaskAttentionCount() }
            }
        }
        .fileImporter(isPresented: $isShowingImportPicker, allowedContentTypes: [.tabSeparatedText, .commaSeparatedText, .plainText, .data]) { result in
            switch result {
            case .success(let url):
                Task { await submitImport(fileURL: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
        .sheet(item: $editingCell) { target in
            MetadataValueEditSheet(column: target.column, sampleIndex: target.sampleIndex, projectServerID: projectServerID, ontologyStore: ontologyStore)
        }
        .sheet(item: $columnSettingsTarget) { column in
            MetadataColumnSettingsSheet(column: column.asDTO) { _ in }
        }
        .sheet(item: $autofillTarget) { column in
            MetadataColumnAutofillSheet(
                column: column.asDTO,
                metadataTableServerID: metadataTableServerID,
                sampleCount: sampleCount,
                allColumns: columns.map(\.asDTO)
            ) {
                await refreshColumns()
            }
        }
        .sheet(item: $findReplaceTarget) { column in
            ColumnFindReplaceSheet(column: column.asDTO) {
                await refreshColumns()
            }
        }
        .task {
            await refreshColumns()
            await loadPools()
        }
        .task {
            await refreshAsyncTaskAttentionCount()
            for await _ in await appSession.asyncTaskEvents() {
                await refreshAsyncTaskAttentionCount()
            }
        }
    }

    @ViewBuilder
    private var listModeContent: some View {
        Section("Columns") {
            if columns.isEmpty {
                Text("No columns match this filter.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(columns) { column in
                    HStack {
                        Button {
                            openCellEditor(column: column, sampleIndex: nil)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(column.displayName ?? column.name)
                                    if column.mandatory {
                                        Image(systemName: "asterisk")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                    if column.hidden {
                                        Image(systemName: "eye.slash")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if column.readonly {
                                        Image(systemName: "lock")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if column.staffOnly {
                                        Image(systemName: "lock.shield")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    if column.ontologyType != nil {
                                        Image(systemName: "list.bullet.rectangle")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(column.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        .accessibilityIdentifier("metadataTableListRow_\(column.name)")
                        Spacer()
                        Menu {
                            Button {
                                columnSettingsTarget = column
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .accessibilityIdentifier("metadataTableColumnSettingsMenuItem_\(column.name)")
                            Button {
                                autofillTarget = column
                            } label: {
                                Label("Autofill", systemImage: "wand.and.stars")
                            }
                            .accessibilityIdentifier("metadataTableColumnAutofillMenuItem_\(column.name)")
                            Button {
                                findReplaceTarget = column
                            } label: {
                                Label("Find & Replace", systemImage: "text.magnifyingglass")
                            }
                            .accessibilityIdentifier("metadataTableColumnFindReplaceMenuItem_\(column.name)")
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("metadataTableColumnMenu_\(column.name)")
                        .help("Column Actions")
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            columnSettingsTarget = column
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tint(.gray)
                        .accessibilityIdentifier("metadataTableColumnSettingsButton_\(column.name)")
                        Button {
                            autofillTarget = column
                        } label: {
                            Label("Autofill", systemImage: "wand.and.stars")
                        }
                        .tint(.purple)
                        .accessibilityIdentifier("metadataTableColumnAutofillButton_\(column.name)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tableModeContent: some View {
        Section {
            HStack {
                Picker("Page Size", selection: $pageSize) {
                    ForEach(Self.pageSizes, id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .accessibilityIdentifier("metadataTablePageSizePicker")
                .onChange(of: pageSize) { currentPage = 1 }
                Spacer()
                Button {
                    currentPage = max(1, currentPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentPage <= 1)
                .accessibilityIdentifier("metadataTablePreviousPageButton")
                .help("Previous Page")
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                Button {
                    currentPage = min(totalPages, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentPage >= totalPages)
                .accessibilityIdentifier("metadataTableNextPageButton")
                .help("Next Page")
            }
        }
        Section("Samples") {
            if columns.isEmpty {
                Text("No columns match this filter.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Sample")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(columns) { column in
                                Text(column.displayName ?? column.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            }
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(pageSampleIndices, id: \.self) { sampleIndex in
                            GridRow {
                                Text("\(sampleIndex)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(columns) { column in
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
                                    .accessibilityIdentifier("metadataTableCell_\(column.name)_\(sampleIndex)")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var samplePoolsSection: some View {
        Section("Sample Pools") {
            if isLoadingPools {
                ProgressView()
            } else {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Pool")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(columns) { column in
                                Text(column.displayName ?? column.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            }
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(samplePools, id: \.id) { pool in
                            GridRow {
                                Text(pool.poolName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(columns) { column in
                                    let poolValue = (pool.metadataColumns ?? []).first(where: { $0.name == column.name })?.value ?? ""
                                    Text(poolValue.isEmpty ? "-" : poolValue)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(minWidth: 80, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func openCellEditor(column: CachedMetadataColumn, sampleIndex: Int?) {
        if PlatformWindowPreference.prefersSeparateWindow {
            openWindow(id: "metadata-value-editor", value: MetadataValueEditWindowID(namespaceID: namespaceID, columnServerID: column.serverID, sampleIndex: sampleIndex, projectServerID: projectServerID))
        } else {
            editingCell = MetadataCellEditTarget(column: column, sampleIndex: sampleIndex)
        }
    }

    private func loadPools() async {
        isLoadingPools = true
        defer { isLoadingPools = false }
        do {
            let services = appSession.makeSyncServices()
            samplePools = try await services.samplePoolSync.fetchDetail(metadataTableServerID: metadataTableServerID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func refreshColumns() async {
        do {
            let services = appSession.makeSyncServices()
            let detail = try await services.metadataTableSync.fetchDetail(tableServerID: metadataTableServerID)
            let tableServerID = metadataTableServerID
            let existing = try modelContext.fetch(
                FetchDescriptor<CachedMetadataColumn>(predicate: #Predicate { $0.metadataTableServerID == tableServerID })
            )
            for column in existing {
                modelContext.delete(column)
            }
            for columnDTO in detail.columns {
                modelContext.insert(CachedMetadataColumn(
                    serverID: columnDTO.id,
                    metadataTableServerID: tableServerID,
                    name: columnDTO.name,
                    displayName: columnDTO.displayName,
                    type: columnDTO.type,
                    columnPosition: columnDTO.columnPosition ?? 0,
                    value: columnDTO.value,
                    notApplicable: columnDTO.notApplicable,
                    notAvailable: columnDTO.notAvailable,
                    mandatory: columnDTO.mandatory,
                    hidden: columnDTO.hidden,
                    readonly: columnDTO.readonly,
                    ontologyType: columnDTO.ontologyType,
                    staffOnly: columnDTO.staffOnly,
                    modifiers: columnDTO.modifiers.map { MetadataColumnModifier(samples: $0.samples, value: $0.value) }
                ))
            }
            try modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private enum ExportFormat {
        case sdrf, excel
    }

    private func submitExport(format: ExportFormat) async {
        switch format {
        case .sdrf: isExportingSDRF = true
        case .excel: isExportingExcel = true
        }
        defer {
            switch format {
            case .sdrf: isExportingSDRF = false
            case .excel: isExportingExcel = false
            }
        }
        do {
            let services = appSession.makeSyncServices()
            let columnIDs = allTableColumns.compactMap(\.serverID)
            let taskID: String
            switch format {
            case .sdrf:
                taskID = try await services.asyncTaskSync.exportSDRFFile(
                    metadataTableServerID: metadataTableServerID, metadataColumnIDs: columnIDs,
                    sampleNumber: sampleCount, includePools: !samplePools.isEmpty
                )
                appSession.recordRetryAction(
                    .exportSDRF(metadataTableServerID: metadataTableServerID, metadataColumnIDs: columnIDs, sampleNumber: sampleCount, includePools: !samplePools.isEmpty),
                    forTaskID: taskID
                )
            case .excel:
                taskID = try await services.asyncTaskSync.exportExcelTemplate(
                    metadataTableServerID: metadataTableServerID, metadataColumnIDs: columnIDs,
                    sampleNumber: sampleCount, includePools: !samplePools.isEmpty
                )
                appSession.recordRetryAction(
                    .exportExcel(metadataTableServerID: metadataTableServerID, metadataColumnIDs: columnIDs, sampleNumber: sampleCount, includePools: !samplePools.isEmpty),
                    forTaskID: taskID
                )
            }
            exportedTaskMessage = "Export queued (task \(taskID.prefix(8))…). Check Async Tasks for progress and download."
            isShowingExportedTaskMessage = true
            await refreshAsyncTaskAttentionCount()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func submitImport(fileURL: URL) async {
        isImporting = true
        defer { isImporting = false }
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            let effectiveImportScope = appSession.isStaff ? importScope : .userMetadata
            let services = appSession.makeSyncServices()
            let taskID = try await services.asyncTaskSync.importSDRFFile(
                metadataTableServerID: metadataTableServerID, fileData: fileData, fileName: fileName,
                replaceExisting: replaceExistingOnImport, importScope: effectiveImportScope
            )
            appSession.recordRetryAction(
                .importSDRF(metadataTableServerID: metadataTableServerID, fileData: fileData, fileName: fileName, replaceExisting: replaceExistingOnImport, importScope: effectiveImportScope),
                forTaskID: taskID
            )
            exportedTaskMessage = "Import queued (task \(taskID.prefix(8))…). Check Async Tasks for progress."
            isShowingExportedTaskMessage = true
            await refreshAsyncTaskAttentionCount()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func refreshAsyncTaskAttentionCount() async {
        do {
            let services = appSession.makeSyncServices()
            let page = try await services.asyncTaskSync.fetchAll(limit: 100)
            pendingAsyncTaskCount = page.results.filter { !$0.isTerminal || $0.status == "FAILURE" }.count
        } catch {
            // Leave the last known count as-is; this is a best-effort indicator, not a source of truth.
        }
    }
}
