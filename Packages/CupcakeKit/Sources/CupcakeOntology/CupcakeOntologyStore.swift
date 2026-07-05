import Foundation
import SwiftData

/// Factory for the ontology `ModelContainer` — a separate store from the app's main
/// `CupcakeStore`, independent lifecycle (read-only after import, safe to blow away/rebuild per
/// table), so it isn't declared alongside the syncable `Cached*` schema in `CupcakeApp.swift`.
public enum CupcakeOntologyStore {
    public static func makeContainer(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(OntologyRegistry.allModelTypes + [OntologyImportState.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemoryOnly)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// A single ontology/column-template/schema `@Model` type's row-mapping — lets
/// `OntologyImportService`/`OntologyStore` handle all of them through one shared, generic
/// import path instead of a bespoke method per type. `typeKey` matches the manifest's own
/// `table.name` (e.g. `"tissue"`, `"species"`, `"system"` for column-template, `"sdrf"` for the
/// schema dataset) — used for `OntologyImportState` bookkeeping and the settings UI.
///
/// `sqlTableName` is a **separate** concern: the actual table name inside the `.sqlite` file,
/// which is *not* always the same as `typeKey` — confirmed by actually opening the real
/// downloaded files, not assumed. For the 14 ontology tables the two coincide (internal table
/// `tissue` for manifest name `"tissue"`), but the column-template dataset's manifest name is
/// `"system"` while its internal table is `column_template`, and the schema dataset's manifest
/// name is `"sdrf"` while its internal table is `schema`.
public protocol OntologyRowDecodable: PersistentModel {
    static var typeKey: String { get }
    static var sqlTableName: String { get }
    /// `nil` if the row is missing something this type treats as required (e.g. no primary
    /// identifier) — such rows are skipped, not treated as a fatal import error.
    init?(row: [String: String?])
}

extension OntologyRowDecodable {
    /// Coincides with `typeKey` for all 14 ontology tables — only `CachedColumnTemplate`/
    /// `CachedSDRFSchema` need to override this.
    public static var sqlTableName: String { typeKey }
}

/// Orchestrates fetch -> decompress -> parse -> upsert for one ontology table at a time.
/// Network/decompression work happens here; SwiftData access is isolated to `OntologyStore`
/// (a `@ModelActor`, same reasoning as every `*Store` in `CupcakeSync` — the macro synthesizes
/// its own initializer bound only to `modelContainer`, so it can't hold this actor's other
/// stored properties alongside it).
public actor OntologyImportService {
    private let releaseClient: OntologyReleaseClient
    private let store: OntologyStore

    public init(modelContainer: ModelContainer, releaseClient: OntologyReleaseClient = OntologyReleaseClient()) {
        self.releaseClient = releaseClient
        self.store = OntologyStore(modelContainer: modelContainer)
    }

    public func fetchManifest() async throws -> OntologyManifest {
        try await releaseClient.fetchManifest()
    }

    /// Downloads, decompresses, and imports one table, replacing whatever was previously
    /// imported for it — each table's import is a full replace, not a merge/diff, since there's
    /// no per-row identity to reconcile against, just a from-scratch snapshot on every import.
    public func importTable<T: OntologyRowDecodable>(_ type: T.Type, table: OntologyManifestTable) async throws {
        let decompressed = try await releaseClient.downloadTable(table)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try decompressed.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var rows: [[String: String?]] = []
        try SQLiteTableReader.readRows(from: tempFile, table: T.sqlTableName) { row in
            rows.append(row)
        }
        let importedCount = try await store.replace(type, rows: rows)
        try await store.markImported(typeKey: T.typeKey, rowCount: importedCount)
    }

    public func importState(typeKey: String) async throws -> OntologyImportStateSnapshot? {
        try await store.importState(typeKey: typeKey)
    }

    public func setEnabled(typeKey: String, isEnabled: Bool) async throws {
        try await store.setEnabled(typeKey: typeKey, isEnabled: isEnabled)
    }
}

public struct OntologyImportStateSnapshot: Sendable {
    public let isEnabled: Bool
    public let importedAt: Date?
    public let rowCount: Int?
}

@ModelActor
actor OntologyStore {
    /// Returns the number of rows actually inserted (rows a type's `init?(row:)` rejected as
    /// malformed are silently skipped, not counted).
    @discardableResult
    func replace<T: OntologyRowDecodable>(_ type: T.Type, rows: [[String: String?]]) throws -> Int {
        try modelContext.delete(model: T.self)
        var count = 0
        for row in rows {
            guard let model = T(row: row) else { continue }
            modelContext.insert(model)
            count += 1
        }
        try modelContext.save()
        return count
    }

    func markImported(typeKey: String, rowCount: Int) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<OntologyImportState>(predicate: #Predicate { $0.typeKey == typeKey })
        )
        let state = existing.first ?? {
            let created = OntologyImportState(typeKey: typeKey, isEnabled: true)
            modelContext.insert(created)
            return created
        }()
        state.importedAt = Date()
        state.rowCount = rowCount
        state.isEnabled = true
        try modelContext.save()
    }

    func importState(typeKey: String) throws -> OntologyImportStateSnapshot? {
        guard let state = try modelContext.fetch(
            FetchDescriptor<OntologyImportState>(predicate: #Predicate { $0.typeKey == typeKey })
        ).first else { return nil }
        return OntologyImportStateSnapshot(isEnabled: state.isEnabled, importedAt: state.importedAt, rowCount: state.rowCount)
    }

    func setEnabled(typeKey: String, isEnabled: Bool) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<OntologyImportState>(predicate: #Predicate { $0.typeKey == typeKey })
        )
        let state = existing.first ?? {
            let created = OntologyImportState(typeKey: typeKey)
            modelContext.insert(created)
            return created
        }()
        state.isEnabled = isEnabled
        try modelContext.save()
    }
}
