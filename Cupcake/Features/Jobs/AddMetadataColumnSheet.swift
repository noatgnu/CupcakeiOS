import CupcakeModels
import CupcakeNetworking
import CupcakeOntology
import CupcakeSync
import SwiftData
import SwiftUI

struct AddMetadataColumnSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage("defaultSDRFSchema") private var defaultSchemaName: String = ""

    let tableServerID: Int64
    let ontologyStore: ModelContainer
    let onColumnAdded: () async -> Void

    @State private var searchText = ""
    @State private var groupedResults: [GroupedColumnTemplateDTO] = []
    @State private var offlineResults: [CachedColumnTemplate] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingManagementSheet = false
    @State private var schemaPickerTarget: GroupedColumnTemplateDTO?

    var body: some View {
        NavigationStack {
            Form {
                Section("Search Templates") {
                    TextField("Column name", text: $searchText)
                        .accessibilityIdentifier("addColumnSearchField")
                        .onChange(of: searchText) {
                            scheduleSearch()
                        }
                }
                Section {
                    Button("Manage My Templates…") {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "column-template-manager", using: openWindow)
                        } else {
                            isShowingManagementSheet = true
                        }
                    }
                    .accessibilityIdentifier("manageColumnTemplatesButton")
                }
                if !groupedResults.isEmpty {
                    Section("Results") {
                        ForEach(groupedResults, id: \.columnName) { group in
                            Button {
                                Task { await selectGroup(group) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.sampleTemplate?.name ?? group.columnName)
                                    HStack(spacing: 4) {
                                        Text(group.columnName)
                                        if group.schemaCount > 1 {
                                            Text("· \(group.schemaCount) schemas")
                                        } else if let schema = group.schemas.first {
                                            Text("· \(schema)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("addColumnGroupRow_\(group.columnName)")
                        }
                    }
                } else if !offlineResults.isEmpty {
                    Section("Results (Offline)") {
                        ForEach(offlineResults) { template in
                            Button {
                                Task { await addColumn(offline: template) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name ?? template.columnName ?? "")
                                    if let columnName = template.columnName {
                                        Text(columnName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("addColumnOfflineRow_\(template.serverID)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Column")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 400)
        .alert("Couldn't add column", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingManagementSheet) {
            NavigationStack {
                ColumnTemplateManagementSheet()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isShowingManagementSheet = false }
                        }
                    }
            }
            .frame(minWidth: 380, minHeight: 420)
        }
        .sheet(item: $schemaPickerTarget) { group in
            NavigationStack {
                List(group.schemas, id: \.self) { schema in
                    Button(schema) {
                        Task { await addColumn(columnName: group.columnName, schema: schema) }
                    }
                    .accessibilityIdentifier("addColumnSchemaOption_\(schema)")
                }
                .navigationTitle("Choose Schema")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { schemaPickerTarget = nil }
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 360)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard searchText.count >= 3 else {
                groupedResults = []
                offlineResults = []
                return
            }
            do {
                let services = appSession.makeSyncServices()
                let found = try await services.metadataColumnTemplateSync.searchGrouped(query: searchText)
                guard !Task.isCancelled else { return }
                groupedResults = found
                offlineResults = []
            } catch {
                guard !Task.isCancelled else { return }
                groupedResults = []
                offlineResults = searchOfflineColumnTemplates(matching: searchText)
            }
        }
    }

    private func searchOfflineColumnTemplates(matching text: String) -> [CachedColumnTemplate] {
        let context = ModelContext(ontologyStore)
        let all = (try? context.fetch(FetchDescriptor<CachedColumnTemplate>())) ?? []
        return all.filter {
            ($0.name?.localizedCaseInsensitiveContains(text) ?? false) || ($0.columnName?.localizedCaseInsensitiveContains(text) ?? false)
        }
    }

    private func selectGroup(_ group: GroupedColumnTemplateDTO) async {
        if group.schemaCount <= 1, let template = group.sampleTemplate {
            await addColumn(template)
            return
        }
        if !defaultSchemaName.isEmpty, group.schemas.contains(defaultSchemaName) {
            await addColumn(columnName: group.columnName, schema: defaultSchemaName)
            return
        }
        schemaPickerTarget = group
    }

    private func addColumn(columnName: String, schema: String) async {
        guard !isSaving else { return }
        do {
            let services = appSession.makeSyncServices()
            let matches = try await services.metadataColumnTemplateSync.search(query: columnName, sourceSchema: schema, limit: 1)
            guard let template = matches.first else {
                errorMessage = "No template found for \"\(columnName)\" in schema \"\(schema)\"."
                isShowingError = true
                return
            }
            schemaPickerTarget = nil
            await addColumn(template)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func addColumn(offline template: CachedColumnTemplate) async {
        guard !isSaving, let columnName = template.columnName, let columnType = template.columnType else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataColumnSync.addColumn(
                tableServerID: tableServerID,
                columnData: AddColumnDataRequest(
                    name: columnName,
                    type: columnType,
                    ontologyType: template.ontologyType,
                    value: template.defaultValue
                )
            )
            await onColumnAdded()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func addColumn(_ template: MetadataColumnTemplateDTO) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataColumnSync.addColumn(
                tableServerID: tableServerID,
                columnData: AddColumnDataRequest(
                    name: template.columnName,
                    type: template.columnType,
                    ontologyType: template.ontologyType,
                    value: template.defaultValue
                )
            )
            await onColumnAdded()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

extension GroupedColumnTemplateDTO: Identifiable {
    public var id: String { columnName }
}
