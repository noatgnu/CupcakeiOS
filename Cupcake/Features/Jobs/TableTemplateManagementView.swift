import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct TableTemplateManagementView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<CachedMetadataTableTemplate> { $0.canEdit }, sort: \CachedMetadataTableTemplate.createdAt, order: .reverse)
    private var templates: [CachedMetadataTableTemplate]

    let ontologyStore: ModelContainer

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Templates")]
    @State private var selectedTemplateServerID: Int64?
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingNewTemplateSheet = false
    @State private var currentPage = 0
    @State private var searchText = ""
    private let pageSize = 20

    private var searchedTemplates: [CachedMetadataTableTemplate] {
        guard !searchText.isEmpty else { return templates }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(searchedTemplates.count) / Double(pageSize))))
    }

    private var pagedTemplates: [CachedMetadataTableTemplate] {
        let start = currentPage * pageSize
        guard start < searchedTemplates.count else { return [] }
        return Array(searchedTemplates[start..<min(start + pageSize, searchedTemplates.count)])
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            List {
                if templates.isEmpty {
                    Text("No metadata table templates you can manage yet.")
                        .foregroundStyle(.secondary)
                } else if searchedTemplates.isEmpty {
                    Text("No templates match \"\(searchText)\".")
                        .foregroundStyle(.secondary)
                } else {
                    Section("My Templates (\(searchedTemplates.count))") {
                        ForEach(pagedTemplates) { template in
                            templateRow(template)
                        }
                        .onDelete { offsets in
                            Task { await deleteTemplates(at: offsets) }
                        }
                    }
                    if totalPages > 1 {
                        paginationControls
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewTemplateSheet = true
                    } label: {
                        Label("New Template…", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("newMetadataTableTemplateButton")
                }
            }
        } detail: {
            if let selectedTemplateServerID, let selected = templates.first(where: { $0.serverID == selectedTemplateServerID }) {
                TableTemplateDetailView(template: selected.asDTO) { updated in
                    applyUpdate(updated, to: selected)
                } onColumnCountChanged: { newCount in
                    selected.columnCount = newCount
                    try? modelContext.save()
                }
                .id(selected.serverID)
            } else {
                ContentUnavailableView(
                    "No Template Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a template to view and edit its columns.")
                )
            }
        } sidebarHeader: {
            if !templates.isEmpty {
                TextField("Search templates", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("myTableTemplateSearchField")
                    .onChange(of: searchText) { currentPage = 0 }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
        .alert("Couldn't update templates", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingNewTemplateSheet) {
            NewMetadataTableTemplateSheet(jobLabGroupServerID: nil, ontologyStore: ontologyStore) { _ in }
        }
        .onChange(of: selectedTemplateServerID) { _, newValue in
            guard let newValue, let template = templates.first(where: { $0.serverID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: nil, name: template.name)]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedTemplateServerID = nil
            }
        }
        .closableWindowToolbar(id: "table-template-manager")
    }

    private var paginationControls: some View {
        HStack {
            Button("Previous") { currentPage -= 1 }
                .disabled(currentPage == 0)
                .accessibilityIdentifier("myTableTemplatePreviousPageButton")
            Spacer()
            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Next") { currentPage += 1 }
                .disabled(currentPage >= totalPages - 1)
                .accessibilityIdentifier("myTableTemplateNextPageButton")
        }
    }

    private func templateRow(_ template: CachedMetadataTableTemplate) -> some View {
        HStack {
            Button {
                selectedTemplateServerID = template.serverID
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                    HStack(spacing: 6) {
                        Text("\(template.columnCount) columns")
                        if !template.schemaNames.isEmpty {
                            Text("· " + template.schemaNames.joined(separator: ", "))
                        }
                        if selectedTemplateServerID == template.serverID {
                            Image(systemName: "checkmark")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("myTableTemplateRow_\(template.name)")
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await duplicate(template) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)
            .accessibilityIdentifier("duplicateTableTemplateButton_\(template.name)")
        }
        .contextMenu {
            Button {
                Task { await duplicate(template) }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .accessibilityIdentifier("duplicateTableTemplateMenuButton_\(template.name)")
        }
    }

    private func applyUpdate(_ dto: MetadataTableTemplateDTO, to cached: CachedMetadataTableTemplate) {
        cached.name = dto.name
        cached.templateDescription = dto.description
        cached.visibility = dto.visibility
        cached.labGroupServerID = dto.labGroup
        try? modelContext.save()
    }

    private func deleteTemplates(at offsets: IndexSet) async {
        let templatesToDelete = offsets.map { pagedTemplates[$0] }
        do {
            let services = appSession.makeSyncServices()
            for template in templatesToDelete {
                try await services.metadataTableTemplateSync.delete(templateServerID: template.serverID)
                if selectedTemplateServerID == template.serverID {
                    selectedTemplateServerID = nil
                }
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func duplicate(_ template: CachedMetadataTableTemplate) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.metadataTableTemplateSync.duplicate(templateServerID: template.serverID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

private extension CachedMetadataTableTemplate {
    var asDTO: MetadataTableTemplateDTO {
        MetadataTableTemplateDTO(
            id: serverID,
            name: name,
            description: templateDescription,
            ownerUsername: ownerUsername,
            visibility: visibility,
            isDefault: isDefault,
            columnCount: columnCount,
            labGroup: labGroupServerID,
            canEdit: canEdit,
            canDelete: canDelete,
            schemaNames: schemaNames
        )
    }
}
