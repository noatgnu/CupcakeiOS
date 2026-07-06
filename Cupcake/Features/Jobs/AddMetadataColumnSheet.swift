import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct AddMetadataColumnSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let tableServerID: Int64
    let onColumnAdded: () async -> Void

    @State private var searchText = ""
    @State private var results: [MetadataColumnTemplateDTO] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingManagementSheet = false

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
                        isShowingManagementSheet = true
                    }
                    .accessibilityIdentifier("manageColumnTemplatesButton")
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { template in
                            Button {
                                Task { await addColumn(template) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                    Text(template.columnName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("addColumnTemplateRow_\(template.name)")
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
            ColumnTemplateManagementSheet()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let services = appSession.makeSyncServices()
                let found = try await services.metadataColumnTemplateSync.search(query: searchText)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
            }
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
