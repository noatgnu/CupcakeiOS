import CupcakeModels
import Foundation
import SwiftData

@ModelActor
public actor OfflineOntologySearchService {
    public func search(text: String, enabledTypeKeys: Set<String>, matchType: OntologyMatchType = .contains, limitPerType: Int = 25) throws -> [String: [OntologyBrowserResult]] {
        guard text.count >= 2 else { return [:] }
        var buckets: [String: [OntologyBrowserResult]] = [:]
        for typeKey in enabledTypeKeys {
            let results = try Self.searchResults(typeKey: typeKey, text: text, matchType: matchType, in: modelContext, limit: limitPerType)
            if !results.isEmpty {
                buckets[typeKey] = results
            }
        }
        return buckets
    }

    public func enabledTypeKeys() throws -> Set<String> {
        let states = try modelContext.fetch(FetchDescriptor<OntologyImportState>())
        return Set(states.filter { $0.isEnabled && $0.importedAt != nil }.map(\.typeKey))
    }

    private static func searchResults(typeKey: String, text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        switch typeKey {
        case CachedTissue.typeKey: try CachedTissue.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedSpecies.typeKey: try CachedSpecies.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedHumanDisease.typeKey: try CachedHumanDisease.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedSubcellularLocation.typeKey: try CachedSubcellularLocation.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedUnimod.typeKey: try CachedUnimod.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedMSUniqueVocabularies.typeKey: try CachedMSUniqueVocabularies.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedNCBITaxonomy.typeKey: try CachedNCBITaxonomy.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedChEBICompound.typeKey: try CachedChEBICompound.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedMondoDisease.typeKey: try CachedMondoDisease.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedUberonAnatomy.typeKey: try CachedUberonAnatomy.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedCellOntology.typeKey: try CachedCellOntology.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedPSIMSOntology.typeKey: try CachedPSIMSOntology.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedBTOTerm.typeKey: try CachedBTOTerm.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        case CachedDiseaseOntologyTerm.typeKey: try CachedDiseaseOntologyTerm.searchResults(matching: text, matchType: matchType, in: context, limit: limit)
        default: []
        }
    }
}
