import Foundation
import SwiftData
import Testing

@testable import CupcakeOntology

/// Deliberately hits the real, public `noatgnu/cupcake-webgui` GitHub release, no mocking.
@Suite("CupcakeOntology live release")
struct CupcakeOntologyTests {
    @Test("fetchManifest decodes a real manifest from the live release")
    func fetchManifestReal() async throws {
        let client = OntologyReleaseClient()
        let manifest = try await client.fetchManifest()

        #expect(manifest.formatVersion == 1)
        #expect(manifest.tables.contains { $0.dataset == "ontology" && $0.name == "tissue" })
        #expect(manifest.tables.contains { $0.dataset == "column-template" && $0.name == "system" })
        #expect(manifest.tables.contains { $0.dataset == "schema" && $0.name == "sdrf" })
    }

    @Test("downloadTable fetches and correctly gzip-decompresses the real tissue table into a valid SQLite file")
    func downloadTissueTableReal() async throws {
        let client = OntologyReleaseClient()
        let manifest = try await client.fetchManifest()
        guard let tissueTable = manifest.tables.first(where: { $0.dataset == "ontology" && $0.name == "tissue" }) else {
            Issue.record("tissue table missing from live manifest")
            return
        }

        let decompressed = try await client.downloadTable(tissueTable)
        #expect(Int64(decompressed.count) == tissueTable.uncompressedBytes)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try decompressed.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var rows: [[String: String?]] = []
        try SQLiteTableReader.readRows(from: tempFile, table: "tissue") { row in
            rows.append(row)
        }

        #expect(rows.count == tissueTable.rowCount)
        #expect(rows.first?["identifier"] != nil)
    }

    @Test("OntologyImportService imports the real tissue table end to end into its own store")
    func importTissueEndToEnd() async throws {
        let container = try CupcakeOntologyStore.makeContainer(inMemoryOnly: true)
        let service = OntologyImportService(modelContainer: container)

        let manifest = try await service.fetchManifest()
        guard let tissueTable = manifest.tables.first(where: { $0.dataset == "ontology" && $0.name == "tissue" }) else {
            Issue.record("tissue table missing from live manifest")
            return
        }

        try await service.importTable(CachedTissue.self, table: tissueTable)

        let context = ModelContext(container)
        let tissues = try context.fetch(FetchDescriptor<CachedTissue>())
        #expect(tissues.count == tissueTable.rowCount)
        #expect(tissues.contains { $0.identifier == "Abdomen" && $0.accession == "TS-0001" })

        let state = try await service.importState(typeKey: "tissue")
        #expect(state?.isEnabled == true)
        #expect(state?.rowCount == tissueTable.rowCount)
        #expect(state?.importedAt != nil)
    }

    @Test("OntologyImportService imports a second, differently-shaped table (species) through the same generic path")
    func importSpeciesEndToEnd() async throws {
        let container = try CupcakeOntologyStore.makeContainer(inMemoryOnly: true)
        let service = OntologyImportService(modelContainer: container)

        let manifest = try await service.fetchManifest()
        guard let speciesTable = manifest.tables.first(where: { $0.dataset == "ontology" && $0.name == "species" }) else {
            Issue.record("species table missing from live manifest")
            return
        }

        try await service.importTable(CachedSpecies.self, table: speciesTable)

        let context = ModelContext(container)
        let species = try context.fetch(FetchDescriptor<CachedSpecies>())
        #expect(species.count == speciesTable.rowCount)
        #expect(species.contains { $0.code == "MLVAT" && $0.taxon == 11790 })

        let state = try await service.importState(typeKey: "species")
        #expect(state?.rowCount == speciesTable.rowCount)
    }

    @Test("OntologyImportService imports the column-template dataset, keyed by its 'system' name not 'column-template'")
    func importColumnTemplateEndToEnd() async throws {
        let container = try CupcakeOntologyStore.makeContainer(inMemoryOnly: true)
        let service = OntologyImportService(modelContainer: container)

        let manifest = try await service.fetchManifest()
        guard let columnTemplateTable = manifest.tables.first(where: { $0.dataset == "column-template" }) else {
            Issue.record("column-template table missing from live manifest")
            return
        }
        #expect(columnTemplateTable.name == "system")

        try await service.importTable(CachedColumnTemplate.self, table: columnTemplateTable)

        let context = ModelContext(container)
        let templates = try context.fetch(FetchDescriptor<CachedColumnTemplate>())
        #expect(templates.count == columnTemplateTable.rowCount)
        #expect(templates.contains { $0.ontologyType != nil })
    }

    @Test("OntologyImportService imports the schema dataset, keyed by its 'sdrf' name not 'schema'")
    func importSDRFSchemaEndToEnd() async throws {
        let container = try CupcakeOntologyStore.makeContainer(inMemoryOnly: true)
        let service = OntologyImportService(modelContainer: container)

        let manifest = try await service.fetchManifest()
        guard let schemaTable = manifest.tables.first(where: { $0.dataset == "schema" }) else {
            Issue.record("schema table missing from live manifest")
            return
        }
        #expect(schemaTable.name == "sdrf")

        try await service.importTable(CachedSDRFSchema.self, table: schemaTable)

        let context = ModelContext(container)
        let schemas = try context.fetch(FetchDescriptor<CachedSDRFSchema>())
        #expect(schemas.count == schemaTable.rowCount)
        #expect(schemas.contains { $0.name == "base" })
    }
}
