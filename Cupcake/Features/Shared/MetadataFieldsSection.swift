import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct MetadataFieldsSection: View {
    let metadataTableServerID: Int64?
    let ontologyStore: ModelContainer
    let onColumnsChanged: () async -> Void
    @Binding var editingColumn: CachedMetadataColumn?
    @Binding var isShowingAddColumnSheet: Bool

    @Environment(AppSession.self) private var appSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.namespaceID) private var namespaceID
    @Query private var allColumns: [CachedMetadataColumn]
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var columns: [CachedMetadataColumn] {
        guard let metadataTableServerID else { return [] }
        return allColumns
            .filter { $0.metadataTableServerID == metadataTableServerID && !$0.hidden }
            .sorted { $0.columnPosition < $1.columnPosition }
    }

    var body: some View {
        Section("Metadata") {
            if let metadataTableServerID {
                if columns.isEmpty {
                    Text("No metadata fields yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(columns) { column in
                        Button {
                            openEditor(for: column)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(column.displayName ?? column.name)
                                    .foregroundStyle(.primary)
                                if let value = column.value, !value.isEmpty {
                                    Text(value)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("metadataColumnRow_\(column.name)")
                    }
                    .onDelete { offsets in
                        Task { await deleteColumns(at: offsets, tableServerID: metadataTableServerID) }
                    }
                }
                Button {
                    isShowingAddColumnSheet = true
                } label: {
                    Label("Add Metadata Field", systemImage: "plus")
                }
                .accessibilityIdentifier("addMetadataFieldButton")
            } else {
                Text("Metadata isn't available yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Couldn't remove field", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func openEditor(for column: CachedMetadataColumn) {
        if PlatformWindowPreference.prefersSeparateWindow {
            openWindow(id: "metadata-value-editor", value: MetadataValueEditWindowID(namespaceID: namespaceID, columnServerID: column.serverID, sampleIndex: nil, projectServerID: nil))
        } else {
            editingColumn = column
        }
    }

    private func deleteColumns(at offsets: IndexSet, tableServerID: Int64) async {
        let columnsToRemove = offsets.map { columns[$0] }
        do {
            let services = appSession.makeSyncServices()
            for column in columnsToRemove {
                try await services.metadataColumnSync.removeColumn(tableServerID: tableServerID, columnServerID: column.serverID)
            }
            await onColumnsChanged()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
