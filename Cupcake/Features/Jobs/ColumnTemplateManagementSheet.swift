import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct ColumnTemplateManagementSheet: View {
    @Environment(AppSession.self) private var appSession

    @State private var templates: [MetadataColumnTemplateDTO] = []
    @State private var isLoading = false
    @State private var editingTemplate: MetadataColumnTemplateDTO?
    @State private var isShowingNewTemplateSheet = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Form {
            if templates.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text("No column templates yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("My Templates") {
                    ForEach(templates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                Text(template.columnName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("myColumnTemplateRow_\(template.name)")
                    }
                    .onDelete { offsets in
                        Task { await deleteTemplates(at: offsets) }
                    }
                }
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

    private func deleteTemplates(at offsets: IndexSet) async {
        let templatesToDelete = offsets.map { templates[$0] }
        do {
            let services = appSession.makeSyncServices()
            for template in templatesToDelete {
                try await services.metadataColumnTemplateSync.delete(templateServerID: template.id)
            }
            await loadTemplates()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
