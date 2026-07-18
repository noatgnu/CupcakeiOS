import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct MetadataTableDetailWindowID: Codable, Hashable {
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
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var columns: [CachedMetadataColumn] {
        allColumns
            .filter { $0.metadataTableServerID == metadataTableServerID }
            .filter { columnFilter.isEmpty || ($0.displayName ?? $0.name).localizedCaseInsensitiveContains(columnFilter) }
            .sorted { $0.columnPosition < $1.columnPosition }
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
        .alert("Couldn't load sample pools", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
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
        .task {
            await refreshColumns()
            await loadPools()
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
                            editingCell = MetadataCellEditTarget(column: column, sampleIndex: nil)
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
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("metadataTableColumnMenu_\(column.name)")
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
                Text("Page \(currentPage) of \(totalPages)")
                    .font(.caption)
                Button {
                    currentPage = min(totalPages, currentPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentPage >= totalPages)
                .accessibilityIdentifier("metadataTableNextPageButton")
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
                                        editingCell = MetadataCellEditTarget(column: column, sampleIndex: sampleIndex)
                                    } label: {
                                        Text(cellValue.isEmpty ? "—" : cellValue)
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
                                    Text(poolValue.isEmpty ? "—" : poolValue)
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
}
