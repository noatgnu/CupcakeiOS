import CupcakeModels
import Foundation
import SwiftData
import Testing

@testable import CupcakeOntology

@Suite("OfflineOntologySearchService")
struct OfflineOntologySearchServiceTests {
    private func seededContainer() throws -> ModelContainer {
        let container = try CupcakeOntologyStore.makeContainer(inMemoryOnly: true)
        let context = ModelContext(container)

        context.insert(CachedSpecies(code: "HUMAN", officialName: "Homo sapiens", commonName: "Human", synonym: nil))
        context.insert(CachedSpecies(code: "MOUSE", officialName: "Mus musculus", commonName: "Mouse", synonym: nil))
        context.insert(CachedUnimod(accession: "UNIMOD:21", name: "Phospho", unimodDefinition: "Phosphorylation", additionalData: nil))
        context.insert(CachedNCBITaxonomy(taxId: 9606, scientificName: "Homo sapiens", commonName: "Human"))
        context.insert(OntologyImportState(typeKey: "species", isEnabled: true, importedAt: Date(), rowCount: 2))
        context.insert(OntologyImportState(typeKey: "unimod", isEnabled: true, importedAt: Date(), rowCount: 1))
        context.insert(OntologyImportState(typeKey: "ncbi_taxonomy", isEnabled: false, importedAt: nil, rowCount: nil))
        try context.save()
        return container
    }

    @Test("buckets results by database rather than merging them into one flat list")
    func bucketsResultsByDatabase() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let buckets = try await service.search(text: "Homo", enabledTypeKeys: ["species", "ncbi_taxonomy"])

        #expect(buckets["species"]?.count == 1)
        #expect(buckets["ncbi_taxonomy"]?.count == 1)
        if case .simpleTerm(let term) = buckets["species"]?.first {
            #expect(term.title == "Homo sapiens")
        } else {
            Issue.record("expected a .simpleTerm result for species")
        }
        if case .taxonomy(let term) = buckets["ncbi_taxonomy"]?.first {
            #expect(term.scientificName == "Homo sapiens")
        } else {
            Issue.record("expected a .taxonomy result for ncbi_taxonomy")
        }
    }

    @Test("a database not in the enabled set contributes no results, even if it has a match")
    func excludesDisabledDatabases() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let buckets = try await service.search(text: "Homo", enabledTypeKeys: ["species"])

        #expect(buckets["species"] != nil)
        #expect(buckets["ncbi_taxonomy"] == nil)
    }

    @Test("Unimod results are correctly mapped to the .unimod case, distinct from simpleTerm")
    func unimodMapsToDistinctCase() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let buckets = try await service.search(text: "Phospho", enabledTypeKeys: ["unimod"])

        guard case .unimod(let term) = buckets["unimod"]?.first else {
            Issue.record("expected a .unimod result")
            return
        }
        #expect(term.name == "Phospho")
        #expect(term.accession == "UNIMOD:21")
    }

    @Test("enabledTypeKeys() reflects only imported and enabled import states")
    func enabledTypeKeysReflectsImportState() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let enabled = try await service.enabledTypeKeys()
        #expect(enabled.contains("species"))
        #expect(enabled.contains("unimod"))
        #expect(!enabled.contains("ncbi_taxonomy"))
    }

    @Test("a search under 2 characters returns no results without querying any database")
    func skipsShortSearch() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let buckets = try await service.search(text: "H", enabledTypeKeys: ["species"])
        #expect(buckets.isEmpty)
    }

    @Test(".contains matches a term in the middle of a field, .startsWith does not")
    func matchTypeDistinguishesContainsFromStartsWith() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let containsBuckets = try await service.search(text: "sapiens", enabledTypeKeys: ["species"], matchType: .contains)
        #expect(containsBuckets["species"]?.count == 1)

        let startsWithBuckets = try await service.search(text: "sapiens", enabledTypeKeys: ["species"], matchType: .startsWith)
        #expect(startsWithBuckets["species"] == nil)
    }

    @Test(".startsWith matches a field that genuinely begins with the search text")
    func startsWithMatchesRealPrefix() async throws {
        let container = try seededContainer()
        let service = OfflineOntologySearchService(modelContainer: container)

        let buckets = try await service.search(text: "Homo", enabledTypeKeys: ["species"], matchType: .startsWith)
        #expect(buckets["species"]?.count == 1)
    }
}
