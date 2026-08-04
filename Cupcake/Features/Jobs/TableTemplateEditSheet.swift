import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct TableTemplateEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var appSession
    @Query private var labGroups: [CachedLabGroup]

    let template: MetadataTableTemplateDTO
    let onSaved: (MetadataTableTemplateDTO) -> Void
    var onColumnCountChanged: (Int) -> Void = { _ in }

    private enum VisibilityOption: String, CaseIterable, Identifiable {
        case `private`
        case group
        case `public`
        var id: String { rawValue }
        var label: String {
            switch self {
            case .private: return "Private"
            case .group: return "Lab Group"
            case .public: return "Public"
            }
        }
    }

    @State private var name: String
    @State private var description: String
    @State private var visibility: VisibilityOption
    @State private var labGroupServerID: Int64?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    @State private var columns: [MetadataColumnDTO] = []
    @State private var columnSearchText = ""
    @State private var isLoadingColumns = false
    @State private var isSelecting = false
    @State private var selectedColumnIDs: Set<Int64> = []
    @State private var settingsTarget: MetadataColumnDTO?
    @State private var isShowingAddColumnSheet = false
    @State private var isBulkWorking = false
    @State private var isSyncingFromSchemas = false
    @State private var syncResultMessage: String?
    @State private var isShowingSyncResult = false

    init(template: MetadataTableTemplateDTO, onSaved: @escaping (MetadataTableTemplateDTO) -> Void, onColumnCountChanged: @escaping (Int) -> Void = { _ in }) {
        self.template = template
        self.onSaved = onSaved
        self.onColumnCountChanged = onColumnCountChanged
        _name = State(initialValue: template.name)
        _description = State(initialValue: template.description ?? "")
        _visibility = State(initialValue: VisibilityOption(rawValue: template.visibility) ?? .private)
        _labGroupServerID = State(initialValue: template.labGroup)
        _columns = State(initialValue: template.userColumns ?? [])
    }

    private var canSave: Bool {
        !name.isEmpty && (visibility != .group || labGroupServerID != nil)
    }

    private var filteredColumns: [MetadataColumnDTO] {
        guard !columnSearchText.isEmpty else { return columns }
        return columns.filter { ($0.displayName ?? $0.name).localizedCaseInsensitiveContains(columnSearchText) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("tableTemplateNameField")
                    TextField("Description", text: $description)
                        .accessibilityIdentifier("tableTemplateDescriptionField")
                }
                if !template.schemaNames.isEmpty {
                    Section("Created From") {
                        ForEach(template.schemaNames, id: \.self) { schemaName in
                            Text(schemaName)
                        }
                        Button {
                            Task { await syncFromSchemas() }
                        } label: {
                            if isSyncingFromSchemas {
                                ProgressView()
                            } else {
                                Text("Sync from Schemas")
                            }
                        }
                        .disabled(isSyncingFromSchemas)
                        .accessibilityIdentifier("syncTemplateFromSchemasButton")
                    }
                }
                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(VisibilityOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .accessibilityIdentifier("tableTemplateVisibilityPicker")
                    if visibility == .group {
                        Picker("Lab Group", selection: $labGroupServerID) {
                            Text("None").tag(Int64?.none)
                            ForEach(labGroups) { labGroup in
                                Text(labGroup.name).tag(Optional(labGroup.serverID))
                            }
                        }
                    }
                }
                columnsSection
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("templateColumnsForm")
            .navigationTitle(template.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveTableTemplateButton")
                }
            }
            .alert("Couldn't save template", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Sync Result", isPresented: $isShowingSyncResult) {
                Button("OK") {}
            } message: {
                Text(syncResultMessage ?? "")
            }
            .sheet(item: $settingsTarget) { column in
                MetadataColumnSettingsSheet(column: column) { updated in
                    if let index = columns.firstIndex(where: { $0.id == updated.id }) {
                        columns[index] = updated
                    }
                }
            }
            .sheet(isPresented: $isShowingAddColumnSheet) {
                AddTemplateColumnSheet(templateServerID: template.id) { added in
                    columns.append(added)
                }
            }
            .task(id: template.id) {
                isLoadingColumns = columns.isEmpty
                await reloadColumns()
                isLoadingColumns = false
            }
            .onChange(of: columns.count) { onColumnCountChanged(columns.count) }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 700)
        #endif
    }

    @ViewBuilder
    private var columnsSection: some View {
        Section {
            HStack {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedColumnIDs = [] }
                }
                .accessibilityIdentifier("templateColumnSelectModeButton")
                Spacer()
                if isSelecting, !selectedColumnIDs.isEmpty {
                    Button("Staff Only") {
                        Task { await bulkSetStaffOnly(true) }
                    }
                    .accessibilityIdentifier("templateColumnBulkStaffOnlyButton")
                    Button("Clear Staff Only") {
                        Task { await bulkSetStaffOnly(false) }
                    }
                    Button("Delete", role: .destructive) {
                        Task { await bulkDelete() }
                    }
                    .accessibilityIdentifier("templateColumnBulkDeleteButton")
                }
            }
        } header: {
            Text("Columns")
        }
        if columns.count > 5 {
            TextField("Search columns", text: $columnSearchText)
                .accessibilityIdentifier("templateColumnSearchField")
        }
        if isLoadingColumns {
            ProgressView()
        } else if columns.isEmpty {
            Text("No columns yet.")
                .foregroundStyle(.secondary)
        } else if filteredColumns.isEmpty {
            Text("No columns match \"\(columnSearchText)\".")
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredColumns) { column in
                if let realIndex = columns.firstIndex(where: { $0.id == column.id }) {
                    columnRow(column, index: realIndex)
                }
            }
        }
        Button {
            isShowingAddColumnSheet = true
        } label: {
            Label("Add Column", systemImage: "plus")
        }
        .accessibilityIdentifier("addTemplateColumnButton")
    }

    @ViewBuilder
    private func columnRow(_ column: MetadataColumnDTO, index: Int) -> some View {
        HStack {
            Button {
                if isSelecting {
                    toggleSelection(column)
                } else {
                    settingsTarget = column
                }
            } label: {
                HStack {
                    if isSelecting {
                        Image(systemName: selectedColumnIDs.contains(column.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedColumnIDs.contains(column.id) ? .blue : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(column.displayName ?? column.name)
                            if column.staffOnly {
                                Image(systemName: "lock.shield")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(column.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("templateColumnRow_\(column.name)")
            Spacer()
            if !isSelecting {
                VStack(spacing: 2) {
                    Button {
                        Task { await moveColumn(column, index: index, delta: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .help("Move Column Up")
                    Button {
                        Task { await moveColumn(column, index: index, delta: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == columns.count - 1)
                    .help("Move Column Down")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    Task { await removeColumn(column) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    Task { await duplicateColumn(column) }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.blue)
                .accessibilityIdentifier("duplicateTemplateColumnButton_\(column.name)")
            }
        }
        .contextMenu {
            if !isSelecting {
                Button {
                    Task { await duplicateColumn(column) }
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .accessibilityIdentifier("duplicateTemplateColumnMenuButton_\(column.name)")
                Button(role: .destructive) {
                    Task { await removeColumn(column) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("deleteTemplateColumnMenuButton_\(column.name)")
            }
        }
    }

    private func toggleSelection(_ column: MetadataColumnDTO) {
        if selectedColumnIDs.contains(column.id) {
            selectedColumnIDs.remove(column.id)
        } else {
            selectedColumnIDs.insert(column.id)
        }
    }

    private func reloadColumns() async {
        do {
            let services = appSession.makeSyncServices()
            let detail = try await services.metadataTableTemplateSync.fetchDetail(templateServerID: template.id)
            columns = detail.userColumns ?? []
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func moveColumn(_ column: MetadataColumnDTO, index: Int, delta: Int) async {
        let newIndex = index + delta
        guard newIndex >= 0, newIndex < columns.count else { return }
        columns.swapAt(index, newIndex)
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.reorderColumn(templateServerID: template.id, columnServerID: column.id, newPosition: newIndex)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
            await reloadColumns()
        }
    }

    private func removeColumn(_ column: MetadataColumnDTO) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.removeColumn(templateServerID: template.id, columnServerID: column.id)
            columns.removeAll { $0.id == column.id }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func duplicateColumn(_ column: MetadataColumnDTO) async {
        do {
            let services = appSession.makeSyncServices()
            let duplicated = try await services.metadataTableTemplateSync.duplicateColumn(templateServerID: template.id, columnServerID: column.id, newName: "\(column.name) (Copy)")
            columns.append(duplicated)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func bulkSetStaffOnly(_ staffOnly: Bool) async {
        guard !selectedColumnIDs.isEmpty else { return }
        isBulkWorking = true
        defer { isBulkWorking = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.bulkUpdateStaffOnly(templateServerID: template.id, columnServerIDs: Array(selectedColumnIDs), staffOnly: staffOnly)
            await reloadColumns()
            selectedColumnIDs = []
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func bulkDelete() async {
        guard !selectedColumnIDs.isEmpty else { return }
        isBulkWorking = true
        defer { isBulkWorking = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.bulkDeleteColumns(templateServerID: template.id, columnServerIDs: Array(selectedColumnIDs))
            columns.removeAll { selectedColumnIDs.contains($0.id) }
            selectedColumnIDs = []
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func syncFromSchemas() async {
        isSyncingFromSchemas = true
        defer { isSyncingFromSchemas = false }
        do {
            let services = appSession.makeSyncServices()
            let result = try await services.metadataTableTemplateSync.syncFromSchemas(templateServerID: template.id)
            syncResultMessage = "Added \(result.added), updated \(result.updated), removed \(result.removed)."
            isShowingSyncResult = true
            await reloadColumns()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let request = CreateMetadataTableTemplateRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            labGroup: visibility == .group ? labGroupServerID : nil,
            visibility: visibility.rawValue
        )
        do {
            let services = appSession.makeSyncServices()
            let updated = try await services.metadataTableTemplateSync.update(templateServerID: template.id, request: request)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

private struct AddTemplateColumnSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let templateServerID: Int64
    let onAdded: (MetadataColumnDTO) -> Void

    private static let columnTypes = ["characteristics", "comment", "factor_value", "source_name", "special"]

    @State private var name = ""
    @State private var type = "characteristics"
    @State private var ontologyType = ""
    @State private var defaultValue = ""
    @State private var autoReorder = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Column") {
                    TextField("Name (SDRF)", text: $name)
                        .accessibilityIdentifier("addTemplateColumnNameField")
                    Picker("Type", selection: $type) {
                        ForEach(Self.columnTypes, id: \.self) { columnType in
                            Text(columnType).tag(columnType)
                        }
                    }
                    TextField("Ontology Type", text: $ontologyType)
                    TextField("Default Value", text: $defaultValue)
                }
                Section {
                    Toggle("Auto-Reorder Using Linked Schemas", isOn: $autoReorder)
                        .accessibilityIdentifier("addTemplateColumnAutoReorderToggle")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Column")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSaving)
                    .accessibilityIdentifier("confirmAddTemplateColumnButton")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 360)
        #endif
        .alert("Couldn't add column", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let columnData = AddColumnDataRequest(
            name: name,
            type: type,
            ontologyType: ontologyType.isEmpty ? nil : ontologyType,
            value: defaultValue.isEmpty ? nil : defaultValue
        )
        do {
            let services = appSession.makeSyncServices()
            let response = try await services.metadataTableTemplateSync.addColumn(templateServerID: templateServerID, columnData: columnData, autoReorder: autoReorder)
            onAdded(response.column)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
