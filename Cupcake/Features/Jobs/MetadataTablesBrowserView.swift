import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct MetadataTablesBrowserView: View {
    let ontologyStore: ModelContainer

    @Environment(AppSession.self) private var appSession
    @Query(sort: \CachedLabGroup.createdAt, order: .reverse) private var labGroups: [CachedLabGroup]

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Metadata Tables")]
    @State private var selectedTableServerID: Int64?

    @State private var searchText = ""
    @State private var labGroupFilter: Int64?
    @State private var showShared = false
    @State private var adminView = false
    @State private var columnName = ""
    @State private var columnValue = ""
    @State private var columnType = ""
    @State private var exactColumnMatch = false
    @State private var isShowingColumnContentSearch = false

    @State private var tables: [MetadataTableDTO] = []
    @State private var totalCount = 0
    @State private var offset = 0
    private let pageSize = 25
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var editingTable: MetadataTableDTO?

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            List {
                if tables.isEmpty {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("No metadata tables found.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Tables (\(totalCount))") {
                        ForEach(tables, id: \.id) { table in
                            tableRow(table)
                        }
                    }
                    if totalCount > pageSize {
                        paginationControls
                    }
                }
            }
            .navigationTitle("Metadata Tables")
        } detail: {
            if let selectedTableServerID, let selected = tables.first(where: { $0.id == selectedTableServerID }) {
                MetadataTableDetailView(
                    metadataTableServerID: selected.id,
                    sampleCount: selected.sampleCount,
                    canEdit: selected.canEdit,
                    projectServerID: nil,
                    ontologyStore: ontologyStore
                )
                .toolbar {
                    if selected.canEdit {
                        ToolbarItem {
                            Button {
                                editingTable = selected
                            } label: {
                                Label("Edit…", systemImage: "pencil")
                            }
                            .accessibilityIdentifier("editMetadataTableButton")
                        }
                    }
                }
                .id(selected.id)
            } else {
                ContentUnavailableView(
                    "No Table Selected",
                    systemImage: "tablecells",
                    description: Text("Select a metadata table to view its columns.")
                )
            }
        } sidebarHeader: {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("metadataTablesBrowserSearchField")
                    .onSubmit { Task { await reloadFromStart() } }
                Picker("Lab Group", selection: $labGroupFilter) {
                    Text("Any").tag(Int64?.none)
                    ForEach(labGroups) { labGroup in
                        Text(labGroup.name).tag(Optional(labGroup.serverID))
                    }
                }
                .onChange(of: labGroupFilter) { Task { await reloadFromStart() } }
                Toggle("Show Shared With Me", isOn: $showShared)
                    .accessibilityIdentifier("metadataTablesShowSharedToggle")
                    .onChange(of: showShared) { Task { await reloadFromStart() } }
                if appSession.isStaff {
                    Toggle("Admin View (All Tables)", isOn: $adminView)
                        .accessibilityIdentifier("metadataTablesAdminViewToggle")
                        .onChange(of: adminView) { Task { await reloadFromStart() } }
                }
                DisclosureGroup("Search by Column Content", isExpanded: $isShowingColumnContentSearch) {
                    TextField("Column Name", text: $columnName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("metadataTablesColumnNameField")
                    TextField("Column Value", text: $columnValue)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("metadataTablesColumnValueField")
                    TextField("Column Type", text: $columnType)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("metadataTablesColumnTypeField")
                    Toggle("Exact Match", isOn: $exactColumnMatch)
                    Button("Search") { Task { await reloadFromStart() } }
                        .accessibilityIdentifier("metadataTablesColumnContentSearchButton")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .alert("Couldn't load tables", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $editingTable) { table in
            MetadataTableEditSheet(table: table) {
                await reload()
            }
        }
        .task {
            await reload()
        }
    }

    private var paginationControls: some View {
        HStack {
            Button("Previous") {
                offset = max(0, offset - pageSize)
                Task { await reload() }
            }
            .disabled(offset == 0)
            .accessibilityIdentifier("metadataTablesPreviousPageButton")
            Spacer()
            Text("\(min(offset + 1, totalCount))-\(min(offset + tables.count, totalCount)) of \(totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Next") {
                offset += pageSize
                Task { await reload() }
            }
            .disabled(offset + pageSize >= totalCount)
            .accessibilityIdentifier("metadataTablesNextPageButton")
        }
    }

    @ViewBuilder
    private func tableRow(_ table: MetadataTableDTO) -> some View {
        HStack {
            Button {
                selectedTableServerID = table.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(table.name)
                        if table.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if table.isPublished {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if selectedTableServerID == table.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    HStack(spacing: 4) {
                        Text("\(table.columnCount) columns")
                        if let sampleRange = table.sampleRange, !sampleRange.isEmpty {
                            Text("· \(sampleRange)")
                        }
                        if let ownerUsername = table.ownerUsername {
                            Text("· \(ownerUsername)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("metadataTableRow_\(table.name)")
        }
        .swipeActions(edge: .trailing) {
            if table.canEdit {
                Button(role: .destructive) {
                    Task { await delete(table) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if table.canEdit {
                Button {
                    editingTable = table
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.gray)
                .accessibilityIdentifier("editMetadataTableButton_\(table.name)")
            }
        }
    }

    private func reloadFromStart() async {
        offset = 0
        await reload()
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        var filters = MetadataTableSyncService.SearchFilters()
        filters.search = searchText
        filters.labGroupServerID = labGroupFilter
        filters.showShared = showShared
        filters.adminView = adminView && appSession.isStaff
        filters.columnName = columnName
        filters.columnValue = columnValue
        filters.columnType = columnType
        filters.exactColumnMatch = exactColumnMatch
        do {
            let services = appSession.makeSyncServices()
            let (count, results) = try await services.metadataTableSync.search(filters: filters, limit: pageSize, offset: offset)
            totalCount = count
            tables = results
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func delete(_ table: MetadataTableDTO) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableSync.delete(tableServerID: table.id)
            if selectedTableServerID == table.id {
                selectedTableServerID = nil
            }
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
