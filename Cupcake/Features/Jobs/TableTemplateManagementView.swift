import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct TableTemplateManagementView: View {
    @Environment(AppSession.self) private var appSession
    @Query(filter: #Predicate<CachedMetadataTableTemplate> { $0.canEdit }, sort: \CachedMetadataTableTemplate.name)
    private var templates: [CachedMetadataTableTemplate]

    @State private var editingTemplate: CachedMetadataTableTemplate?
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Form {
            if templates.isEmpty {
                Text("No metadata table templates you can manage yet.")
                    .foregroundStyle(.secondary)
            } else {
                Section("My Templates") {
                    ForEach(templates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                HStack(spacing: 6) {
                                    Text("\(template.columnCount) columns")
                                    if !template.schemaNames.isEmpty {
                                        Text("· " + template.schemaNames.joined(separator: ", "))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("myTableTemplateRow_\(template.name)")
                    }
                    .onDelete { offsets in
                        Task { await deleteTemplates(at: offsets) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Metadata Table Templates")
        .alert("Couldn't update templates", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $editingTemplate) { template in
            TableTemplateEditSheet(template: template.asDTO) {}
        }
    }

    private func deleteTemplates(at offsets: IndexSet) async {
        let templatesToDelete = offsets.map { templates[$0] }
        do {
            let services = appSession.makeSyncServices()
            for template in templatesToDelete {
                try await services.metadataTableTemplateSync.delete(templateServerID: template.serverID)
            }
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
