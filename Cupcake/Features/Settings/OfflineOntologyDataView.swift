import CupcakeNetworking
import CupcakeOntology
import SwiftData
import SwiftUI

struct OfflineOntologyDataView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var manifest: OntologyManifest?
    @State private var importStates: [String: OntologyImportStateSnapshot] = [:]
    @State private var importingTypeKey: String?
    @State private var isImportingAll = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isLoadingManifest = false

    private var allTablesImported: Bool {
        guard let manifest, !manifest.tables.isEmpty else { return true }
        return manifest.tables.allSatisfy { importStates[$0.name]?.importedAt != nil }
    }

    private var service: OntologyImportService {
        OntologyImportService(modelContainer: modelContext.container)
    }

    private func byteCountText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        List {
            if let manifest {
                ForEach(manifest.tables, id: \.name) { table in
                    row(for: table)
                }
            } else if isLoadingManifest {
                ProgressView("Loading available ontology data…")
            }
        }
        .navigationTitle("Offline Ontology Data")
        .task { await loadManifest() }
        .refreshable { await loadManifest() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isImportingAll {
                    ProgressView()
                } else {
                    Button("Import All") {
                        Task { await importAllTables() }
                    }
                    .accessibilityIdentifier("importAllOntologyButton")
                    .disabled(manifest == nil || importingTypeKey != nil || allTablesImported)
                }
            }
        }
        .alert("Couldn't import", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for table: OntologyManifestTable) -> some View {
        let typeKey = table.name
        let state = importStates[typeKey]
        let isImporting = importingTypeKey == typeKey

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(OntologyRegistry.displayNames[typeKey] ?? typeKey)
                Spacer()
                if isImporting {
                    ProgressView()
                } else {
                    Button(state?.importedAt == nil ? "Import" : "Re-import") {
                        Task { await importTable(table) }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("importOntologyButton_\(typeKey)")
                }
            }
            Text("\(table.rowCount.formatted()) rows · \(byteCountText(table.compressedBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let importedAt = state?.importedAt {
                Text("Imported \(importedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func loadManifest() async {
        isLoadingManifest = true
        defer { isLoadingManifest = false }
        do {
            let fetchedManifest = try await service.fetchManifest()
            manifest = fetchedManifest
            for table in fetchedManifest.tables {
                importStates[table.name] = try await service.importState(typeKey: table.name)
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func importTable(_ table: OntologyManifestTable) async {
        importingTypeKey = table.name
        defer { importingTypeKey = nil }
        do {
            try await OntologyRegistry.importTable(table, using: service)
            importStates[table.name] = try await service.importState(typeKey: table.name)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func importAllTables() async {
        guard let manifest else { return }
        isImportingAll = true
        defer { isImportingAll = false }

        var failedTableNames: [String] = []
        for table in manifest.tables where importStates[table.name]?.importedAt == nil {
            importingTypeKey = table.name
            do {
                try await OntologyRegistry.importTable(table, using: service)
                importStates[table.name] = try await service.importState(typeKey: table.name)
            } catch {
                failedTableNames.append(OntologyRegistry.displayNames[table.name] ?? table.name)
            }
        }
        importingTypeKey = nil

        if !failedTableNames.isEmpty {
            errorMessage = "Couldn't import: \(failedTableNames.joined(separator: ", "))"
            isShowingError = true
        }
    }
}
