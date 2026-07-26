import Foundation
import SwiftData

public enum CupcakeOntologyStore {
    public static func makeContainer(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(OntologyRegistry.allModelTypes + [OntologyImportState.self])
        let configuration: ModelConfiguration
        if inMemoryOnly {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let storeURL = appSupport.appendingPathComponent("CupcakeOntologyStore.store")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

public protocol OntologyRowDecodable: PersistentModel {
    static var typeKey: String { get }
    static var sqlTableName: String { get }
    init?(row: [String: String?])
}

extension OntologyRowDecodable {
    public static var sqlTableName: String { typeKey }
}

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
    private static let saveBatchSize = 2000

    @discardableResult
    func replace<T: OntologyRowDecodable>(_ type: T.Type, rows: [[String: String?]]) throws -> Int {
        try modelContext.delete(model: T.self)
        try modelContext.save()

        func freshBatchContext() -> ModelContext {
            let context = ModelContext(modelContext.container)
            context.autosaveEnabled = false
            return context
        }

        var count = 0
        var batchContext = freshBatchContext()
        for row in rows {
            guard let model = T(row: row) else { continue }
            batchContext.insert(model)
            count += 1
            if count % Self.saveBatchSize == 0 {
                try batchContext.save()
                batchContext = freshBatchContext()
            }
        }
        try batchContext.save()
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
