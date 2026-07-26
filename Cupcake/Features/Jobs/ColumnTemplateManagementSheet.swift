import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct ColumnTemplateManagementSheet: View {
    @Environment(AppSession.self) private var appSession
    @Query(sort: \CachedLabGroup.createdAt, order: .reverse) private var labGroups: [CachedLabGroup]

    private enum ViewMode: String, CaseIterable, Identifiable {
        case flat = "My Templates"
        case grouped = "Grouped"
        var id: String { rawValue }
    }

    private enum VisibilityFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case privateOnly = "Private"
        case group = "Lab Group"
        case publicOnly = "Public"
        var id: String { rawValue }
        var apiValue: String? {
            switch self {
            case .all: return nil
            case .privateOnly: return "private"
            case .group: return "group"
            case .publicOnly: return "public"
            }
        }
    }

    private enum SortField: String, CaseIterable, Identifiable {
        case name = "Name"
        case columnName = "Column Name"
        case columnType = "Type"
        case visibility = "Visibility"
        var id: String { rawValue }
    }

    @State private var viewMode: ViewMode = .flat
    @State private var templates: [MetadataColumnTemplateDTO] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var labGroupFilter: Int64?
    @State private var visibilityFilter: VisibilityFilter = .all
    @State private var sortField: SortField = .name
    @State private var sortAscending = true
    @State private var editingTemplate: MetadataColumnTemplateDTO?
    @State private var isShowingNewTemplateSheet = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var currentPage = 0
    private let pageSize = 20

    @State private var groupSearchText = ""
    @State private var groupedResults: [GroupedColumnTemplateDTO] = []
    @State private var groupSearchTask: Task<Void, Never>?
    @State private var expandedGroupColumnName: String?
    @State private var expandedGroupVariants: [MetadataColumnTemplateDTO] = []
    @State private var isLoadingVariants = false

    private var filteredTemplates: [MetadataColumnTemplateDTO] {
        var result = templates
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) || $0.columnName.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let labGroupFilter {
            result = result.filter { $0.labGroup == labGroupFilter }
        }
        if let apiValue = visibilityFilter.apiValue {
            result = result.filter { $0.visibility == apiValue }
        }
        result.sort { lhs, rhs in
            let ascending: Bool
            switch sortField {
            case .name: ascending = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .columnName: ascending = lhs.columnName.localizedCaseInsensitiveCompare(rhs.columnName) == .orderedAscending
            case .columnType: ascending = lhs.columnType.localizedCaseInsensitiveCompare(rhs.columnType) == .orderedAscending
            case .visibility: ascending = lhs.visibility.localizedCaseInsensitiveCompare(rhs.visibility) == .orderedAscending
            }
            return sortAscending ? ascending : !ascending
        }
        return result
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredTemplates.count) / Double(pageSize))))
    }

    private var pagedTemplates: [MetadataColumnTemplateDTO] {
        let all = filteredTemplates
        let start = currentPage * pageSize
        guard start < all.count else { return [] }
        return Array(all[start..<min(start + pageSize, all.count)])
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
                .accessibilityIdentifier("columnTemplateViewModePicker")
            }
            if viewMode == .flat {
                flatModeContent
            } else {
                groupedModeContent
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Column Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New") {
                    isShowingNewTemplateSheet = true
                }
                .accessibilityIdentifier("newColumnTemplateButton")
            }
        }
        .alert("Couldn't update templates", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingNewTemplateSheet) {
            ColumnTemplateEditSheet(template: nil) {
                await loadTemplates()
            }
        }
        .sheet(item: $editingTemplate) { template in
            ColumnTemplateEditSheet(template: template) {
                await loadTemplates()
            }
        }
        .task {
            await loadTemplates()
        }
    }

    @ViewBuilder
    private var flatModeContent: some View {
        Section("Filters") {
            TextField("Search by name or column", text: $searchText)
                .accessibilityIdentifier("columnTemplateSearchField")
                .onChange(of: searchText) { currentPage = 0 }
            Picker("Lab Group", selection: $labGroupFilter) {
                Text("Any").tag(Int64?.none)
                ForEach(labGroups) { labGroup in
                    Text(labGroup.name).tag(Optional(labGroup.serverID))
                }
            }
            .onChange(of: labGroupFilter) { currentPage = 0 }
            Picker("Visibility", selection: $visibilityFilter) {
                ForEach(VisibilityFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .accessibilityIdentifier("columnTemplateVisibilityFilterPicker")
            .onChange(of: visibilityFilter) { currentPage = 0 }
            HStack {
                Picker("Sort By", selection: $sortField) {
                    ForEach(SortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                Button {
                    sortAscending.toggle()
                } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .accessibilityIdentifier("columnTemplateSortDirectionButton")
                .help(sortAscending ? "Ascending" : "Descending")
            }
        }
        if templates.isEmpty {
            if isLoading {
                ProgressView()
            } else {
                Text("No column templates yet.")
                    .foregroundStyle(.secondary)
            }
        } else if filteredTemplates.isEmpty {
            Text("No templates match these filters.")
                .foregroundStyle(.secondary)
        } else {
            Section("My Templates (\(filteredTemplates.count))") {
                ForEach(pagedTemplates) { template in
                    templateRow(template)
                }
            }
            if totalPages > 1 {
                Section {
                    HStack {
                        Button("Previous") { currentPage -= 1 }
                            .disabled(currentPage == 0)
                            .accessibilityIdentifier("columnTemplatePreviousPageButton")
                        Spacer()
                        Text("Page \(currentPage + 1) of \(totalPages)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Next") { currentPage += 1 }
                            .disabled(currentPage >= totalPages - 1)
                            .accessibilityIdentifier("columnTemplateNextPageButton")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: MetadataColumnTemplateDTO) -> some View {
        Button {
            editingTemplate = template
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                HStack(spacing: 4) {
                    Text(template.columnName)
                    Text("· \(template.visibility)")
                    if let schemaName = template.schemaName {
                        Text("· \(schemaName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("myColumnTemplateRow_\(template.name)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await delete(template) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await duplicate(template) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
            .accessibilityIdentifier("duplicateColumnTemplateButton_\(template.name)")
        }
        .contextMenu {
            Button {
                Task { await duplicate(template) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .accessibilityIdentifier("duplicateColumnTemplateMenuButton_\(template.name)")
            Button(role: .destructive) {
                Task { await delete(template) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteColumnTemplateMenuButton_\(template.name)")
        }
    }

    @ViewBuilder
    private var groupedModeContent: some View {
        Section("Search") {
            TextField("Column name (3+ characters)", text: $groupSearchText)
                .accessibilityIdentifier("columnTemplateGroupSearchField")
                .onChange(of: groupSearchText) { scheduleGroupSearch() }
        }
        if isLoadingVariants && groupedResults.isEmpty {
            ProgressView()
        } else if groupedResults.isEmpty {
            Text(groupSearchText.count >= 3 ? "No matching columns found." : "Type at least 3 characters to search across every schema.")
                .foregroundStyle(.secondary)
        } else {
            Section("Results") {
                ForEach(groupedResults, id: \.columnName) { group in
                    Button {
                        Task { await toggleGroup(group) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(group.sampleTemplate?.name ?? group.columnName)
                                Spacer()
                                Image(systemName: expandedGroupColumnName == group.columnName ? "chevron.up" : "chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(group.columnName) · \(group.schemaCount) schema\(group.schemaCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("columnTemplateGroupRow_\(group.columnName)")

                    if expandedGroupColumnName == group.columnName {
                        if isLoadingVariants {
                            ProgressView()
                        } else {
                            ForEach(expandedGroupVariants) { variant in
                                templateRow(variant)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let services = appSession.makeSyncServices()
            templates = try await services.metadataColumnTemplateSync.myTemplates()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func scheduleGroupSearch() {
        groupSearchTask?.cancel()
        groupSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard groupSearchText.count >= 3 else {
                groupedResults = []
                return
            }
            do {
                let services = appSession.makeSyncServices()
                let found = try await services.metadataColumnTemplateSync.searchGrouped(query: groupSearchText)
                guard !Task.isCancelled else { return }
                groupedResults = found
            } catch {
                guard !Task.isCancelled else { return }
                groupedResults = []
            }
        }
    }

    private func toggleGroup(_ group: GroupedColumnTemplateDTO) async {
        if expandedGroupColumnName == group.columnName {
            expandedGroupColumnName = nil
            expandedGroupVariants = []
            return
        }
        expandedGroupColumnName = group.columnName
        expandedGroupVariants = []
        isLoadingVariants = true
        defer { isLoadingVariants = false }
        let services = appSession.makeSyncServices()
        var variants: [MetadataColumnTemplateDTO] = []
        for schema in group.schemas {
            if let match = try? await services.metadataColumnTemplateSync.search(query: group.columnName, sourceSchema: schema, limit: 1).first {
                variants.append(match)
            }
        }
        expandedGroupVariants = variants
    }

    private func duplicate(_ template: MetadataColumnTemplateDTO) async {
        let request = CreateColumnTemplateRequest(
            name: "\(template.name) (Copy)",
            description: template.description,
            columnName: "\(template.columnName)_copy",
            columnType: template.columnType,
            ontologyType: template.ontologyType,
            defaultValue: template.defaultValue,
            defaultPosition: template.defaultPosition,
            visibility: "private",
            labGroup: template.labGroup,
            category: template.category,
            enableTypeahead: template.enableTypeahead,
            notAvailable: template.notAvailable,
            excelValidation: template.excelValidation,
            tags: template.tags
        )
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataColumnTemplateSync.create(request)
            await loadTemplates()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func delete(_ template: MetadataColumnTemplateDTO) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataColumnTemplateSync.delete(templateServerID: template.id)
            await loadTemplates()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
