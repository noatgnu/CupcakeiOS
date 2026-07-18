import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct TableTemplateDetailView: View {
    @Environment(AppSession.self) private var appSession

    let template: MetadataTableTemplateDTO
    let onSaved: (MetadataTableTemplateDTO) -> Void
    var onColumnCountChanged: (Int) -> Void = { _ in }

    @State private var columns: [MetadataColumnDTO]
    @State private var isLoadingColumns = false
    @State private var isShowingEditSheet = false

    init(template: MetadataTableTemplateDTO, onSaved: @escaping (MetadataTableTemplateDTO) -> Void, onColumnCountChanged: @escaping (Int) -> Void = { _ in }) {
        self.template = template
        self.onSaved = onSaved
        self.onColumnCountChanged = onColumnCountChanged
        _columns = State(initialValue: template.userColumns ?? [])
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Name", value: template.name)
                if let description = template.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                LabeledContent("Visibility", value: template.visibility.capitalized)
            }
            if !template.schemaNames.isEmpty {
                Section("Created From") {
                    ForEach(template.schemaNames, id: \.self) { schemaName in
                        Text(schemaName)
                    }
                }
            }
            Section("Columns (\(columns.count))") {
                if isLoadingColumns {
                    ProgressView()
                } else if columns.isEmpty {
                    Text("No columns yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(columns) { column in
                        HStack(spacing: 4) {
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
                            Spacer()
                        }
                        .accessibilityIdentifier("templateColumnPreviewRow_\(column.name)")
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
                .accessibilityIdentifier("editTableTemplateButton")
            }
        }
        .task(id: template.id) {
            isLoadingColumns = columns.isEmpty
            await reloadColumns()
            isLoadingColumns = false
        }
        .sheet(isPresented: $isShowingEditSheet, onDismiss: {
            Task { await reloadColumns() }
        }) {
            TableTemplateEditSheet(template: template, onSaved: onSaved, onColumnCountChanged: onColumnCountChanged)
        }
    }

    private func reloadColumns() async {
        do {
            let services = appSession.makeSyncServices()
            let detail = try await services.metadataTableTemplateSync.fetchDetail(templateServerID: template.id)
            columns = detail.userColumns ?? []
            onColumnCountChanged(columns.count)
        } catch {
        }
    }
}
