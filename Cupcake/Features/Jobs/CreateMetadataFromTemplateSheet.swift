import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct CreateMetadataFromTemplateSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CachedMetadataTableTemplate.createdAt, order: .reverse) private var templates: [CachedMetadataTableTemplate]

    let jobClientID: UUID
    let jobServerID: Int64
    let jobLabGroupServerID: Int64?
    let defaultSampleCount: Int?
    let onCreated: (Int64) -> Void

    @State private var selectedTemplateID: Int64?
    @State private var sampleCountText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var searchText = ""
    @State private var currentPage = 0
    @State private var categoryFilter: TemplateCategoryFilter = .jobLabGroup
    private let pageSize = 20

    private enum TemplateCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case personal = "Personal"
        case jobLabGroup = "Job's Lab Group"
        case otherLabGroups = "Shared With Me"
        var id: String { rawValue }
    }

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Templates")]
    @State private var previewEntry: TemplateEntry?
    @State private var previewSheetEntry: TemplateEntry?
    @State private var previewColumns: [MetadataColumnDTO] = []
    @State private var previewDescription: String?
    @State private var isLoadingPreview = false
    @State private var previewErrorMessage: String?

    init(jobClientID: UUID, jobServerID: Int64, jobLabGroupServerID: Int64?, defaultSampleCount: Int?, onCreated: @escaping (Int64) -> Void = { _ in }) {
        self.jobClientID = jobClientID
        self.jobServerID = jobServerID
        self.jobLabGroupServerID = jobLabGroupServerID
        self.defaultSampleCount = defaultSampleCount
        self.onCreated = onCreated
        _sampleCountText = State(initialValue: defaultSampleCount.map(String.init) ?? "")
    }

    private var canSave: Bool {
        selectedTemplateID != nil
    }

    private var searchedTemplates: [CachedMetadataTableTemplate] {
        guard !searchText.isEmpty else { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var personalTemplates: [CachedMetadataTableTemplate] {
        searchedTemplates.filter { $0.visibility == "private" }
    }

    private var jobLabGroupTemplates: [CachedMetadataTableTemplate] {
        guard let jobLabGroupServerID else { return [] }
        return searchedTemplates.filter { $0.visibility == "group" && $0.labGroupServerID == jobLabGroupServerID }
    }

    private var sharedWithMeTemplates: [CachedMetadataTableTemplate] {
        searchedTemplates.filter {
            $0.visibility == "public" || ($0.visibility == "group" && $0.labGroupServerID != jobLabGroupServerID)
        }
    }

    private struct TemplateEntry: Identifiable {
        let template: CachedMetadataTableTemplate
        let category: String
        var id: ObjectIdentifier { ObjectIdentifier(template) }
    }

    private var orderedEntries: [TemplateEntry] {
        let all = personalTemplates.map { TemplateEntry(template: $0, category: "Personal") }
            + jobLabGroupTemplates.map { TemplateEntry(template: $0, category: "Job's Lab Group") }
            + sharedWithMeTemplates.map { TemplateEntry(template: $0, category: "Shared With Me") }
        guard categoryFilter != .all else { return all }
        return all.filter { $0.category == categoryFilter.rawValue }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(orderedEntries.count) / Double(pageSize))))
    }

    private var pagedEntries: [TemplateEntry] {
        let start = currentPage * pageSize
        guard start < orderedEntries.count else { return [] }
        return Array(orderedEntries[start..<min(start + pageSize, orderedEntries.count)])
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            List {
                if templates.isEmpty {
                    Text("No metadata table templates available.")
                        .foregroundStyle(.secondary)
                } else if searchedTemplates.isEmpty {
                    Text("No templates match \"\(searchText)\".")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Templates (\(orderedEntries.count))") {
                        ForEach(pagedEntries) { entry in
                            templateRow(entry)
                        }
                    }
                    if totalPages > 1 {
                        paginationControls
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("createMetadataTableButton")
                }
            }
        } detail: {
            if let previewEntry {
                previewBody(for: previewEntry)
            } else {
                previewPlaceholder
            }
        } sidebarHeader: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Count")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Sample count", text: $sampleCountText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("metadataSampleCountField")
                }
                if !templates.isEmpty {
                    TextField("Search templates", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("templateSearchField")
                        .onChange(of: searchText) { currentPage = 0 }
                    HStack {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Category", selection: $categoryFilter) {
                            ForEach(TemplateCategoryFilter.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityIdentifier("templateCategoryFilterPicker")
                        .onChange(of: categoryFilter) { currentPage = 0 }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 460)
        #endif
        .alert("Couldn't create metadata table", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $previewSheetEntry) { entry in
            NavigationStack {
                previewBody(for: entry)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { previewSheetEntry = nil }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 320, minHeight: 420)
            #endif
        }
    }

    private var paginationControls: some View {
        HStack {
            Button("Previous") { currentPage -= 1 }
                .disabled(currentPage == 0)
                .accessibilityIdentifier("templatePreviousPageButton")
            Spacer()
            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Next") { currentPage += 1 }
                .disabled(currentPage >= totalPages - 1)
                .accessibilityIdentifier("templateNextPageButton")
        }
    }

    private func templateRow(_ entry: TemplateEntry) -> some View {
        let template = entry.template
        return HStack {
            Button {
                selectedTemplateID = template.serverID
                if horizontalSizeClass != .compact {
                    previewEntry = entry
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                        Text("\(entry.category) · \(template.columnCount) columns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedTemplateID == template.serverID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("metadataTemplateRow_\(template.name)")
            Button {
                if horizontalSizeClass == .compact {
                    previewSheetEntry = entry
                } else {
                    previewEntry = entry
                }
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("previewTemplateButton_\(template.name)")
            .help("Preview Template")
        }
    }

    private var previewPlaceholder: some View {
        ContentUnavailableView(
            "No Template Selected",
            systemImage: "doc.text.magnifyingglass",
            description: Text("Select or preview a template to see its columns.")
        )
    }

    @ViewBuilder
    private func previewBody(for entry: TemplateEntry) -> some View {
        List {
            if let previewDescription, !previewDescription.isEmpty {
                Section("Description") {
                    Text(previewDescription)
                }
            }
            Section("Columns (\(previewColumns.count))") {
                if previewColumns.isEmpty && !isLoadingPreview && previewErrorMessage == nil {
                    Text("No columns.")
                        .foregroundStyle(.secondary)
                }
                ForEach(previewColumns) { column in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.displayName?.isEmpty == false ? column.displayName! : column.name)
                        Text(column.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let value = column.value, !value.isEmpty {
                            Text("Default: \(value)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .overlay {
            if isLoadingPreview {
                ProgressView()
            } else if let previewErrorMessage {
                ContentUnavailableView(
                    "Couldn't Load Preview",
                    systemImage: "exclamationmark.triangle",
                    description: Text(previewErrorMessage)
                )
            }
        }
        .navigationTitle(entry.template.name)
        .task(id: entry.id) {
            await loadPreview(for: entry.template)
        }
    }

    private func loadPreview(for template: CachedMetadataTableTemplate) async {
        isLoadingPreview = true
        previewErrorMessage = nil
        defer { isLoadingPreview = false }
        do {
            let services = appSession.makeSyncServices()
            let detail = try await services.metadataTableTemplateSync.fetchDetail(templateServerID: template.serverID)
            previewColumns = detail.userColumns ?? []
            previewDescription = detail.description
        } catch {
            previewErrorMessage = error.userFacingMessage
            previewColumns = []
        }
    }

    private func save() async {
        guard let selectedTemplateID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            let table = try await services.instrumentJobSync.createMetadataFromTemplate(
                jobServerID: jobServerID,
                jobClientID: jobClientID,
                templateID: selectedTemplateID,
                sampleCount: Int(sampleCountText)
            )
            onCreated(table.id)
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
