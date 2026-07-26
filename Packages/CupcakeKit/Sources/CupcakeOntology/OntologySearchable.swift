import CupcakeModels
import Foundation
import SwiftData

public protocol OntologySearchable {
    static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult]
}

private func matches(_ matchType: OntologyMatchType, _ text: String, _ fields: String?...) -> Bool {
    fields.contains { matchType.matches($0, text) }
}

private let ontologySearchBatchSize = 5000

func fetchMatchingInBatches<T: PersistentModel>(
    in context: ModelContext,
    sortDescriptor sort: SortDescriptor<T>,
    limit: Int,
    matching predicate: (T) -> Bool
) throws -> [T] {
    var results: [T] = []
    var offset = 0
    while results.count < limit {
        try Task.checkCancellation()
        var descriptor = FetchDescriptor<T>(sortBy: [sort])
        descriptor.fetchLimit = ontologySearchBatchSize
        descriptor.fetchOffset = offset
        let batch = try context.fetch(descriptor)
        if batch.isEmpty { break }
        for item in batch where predicate(item) {
            results.append(item)
            if results.count >= limit { break }
        }
        if batch.count < ontologySearchBatchSize { break }
        offset += ontologySearchBatchSize
    }
    return results
}

extension CachedTissue: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedTissue.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.accession, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.identifier,
                    accession: $0.accession,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.crossReferences,
                    source: .offline
                ))
            }
    }
}

extension CachedSpecies: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedSpecies.code), limit: limit) {
            matches(matchType, text, $0.code, $0.officialName, $0.commonName, $0.synonym)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.code)",
                    typeKey: typeKey,
                    title: $0.officialName ?? $0.commonName ?? $0.code,
                    accession: $0.code,
                    synonyms: [$0.commonName, $0.synonym].compactMap { $0 }.joined(separator: ", "),
                    badge: $0.taxon.map(String.init),
                    source: .offline
                ))
            }
    }
}

extension CachedHumanDisease: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedHumanDisease.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.acronym, $0.accession, $0.synonyms, $0.keywords)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.identifier,
                    accession: $0.accession,
                    definition: $0.diseaseDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.keywords,
                    badge: $0.acronym,
                    source: .offline
                ))
            }
    }
}

extension CachedMSUniqueVocabularies: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedMSUniqueVocabularies.accession), limit: limit) {
            matches(matchType, text, $0.accession, $0.name)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.accession)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.accession,
                    accession: $0.accession,
                    definition: $0.vocabularyDefinition,
                    badge: $0.termType,
                    source: .offline
                ))
            }
    }
}

extension CachedMondoDisease: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedMondoDisease.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.mondoDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    source: .offline
                ))
            }
    }
}

extension CachedUberonAnatomy: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedUberonAnatomy.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.uberonDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    source: .offline
                ))
            }
    }
}

extension CachedCellOntology: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedCellOntology.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms, $0.accession)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.accession ?? $0.identifier,
                    definition: $0.cellDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    source: .offline
                ))
            }
    }
}

extension CachedPSIMSOntology: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedPSIMSOntology.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.psimsDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    badge: $0.category,
                    source: .offline
                ))
            }
    }
}

extension CachedBTOTerm: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedBTOTerm.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.btoDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    source: .offline
                ))
            }
    }
}

extension CachedDiseaseOntologyTerm: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedDiseaseOntologyTerm.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms)
        }
        return rows
            .map {
                .simpleTerm(SimpleOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    typeKey: typeKey,
                    title: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.doidDefinition,
                    synonyms: $0.synonyms,
                    relatedTerms: $0.parentTerms,
                    source: .offline
                ))
            }
    }
}

extension CachedNCBITaxonomy: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedNCBITaxonomy.taxId), limit: limit) {
            matches(matchType, text, $0.scientificName, $0.commonName, $0.synonyms, String($0.taxId))
        }
        return rows
            .map {
                .taxonomy(TaxonomyOntologyTerm(
                    id: "\(typeKey):\($0.taxId)",
                    scientificName: $0.scientificName ?? "Tax ID \($0.taxId)",
                    commonName: $0.commonName,
                    synonyms: $0.synonyms,
                    rank: $0.rank,
                    parentTaxId: $0.parentTaxId,
                    source: .offline
                ))
            }
    }
}

extension CachedChEBICompound: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedChEBICompound.identifier), limit: limit) {
            matches(matchType, text, $0.identifier, $0.name, $0.synonyms, $0.formula)
        }
        return rows
            .map {
                .chemicalCompound(ChemicalCompoundOntologyTerm(
                    id: "\(typeKey):\($0.identifier)",
                    name: $0.name ?? $0.identifier,
                    accession: $0.identifier,
                    definition: $0.chebiDefinition,
                    synonyms: $0.synonyms,
                    formula: $0.formula,
                    mass: $0.mass,
                    charge: $0.charge,
                    inchi: $0.inchi,
                    smiles: $0.smiles,
                    source: .offline
                ))
            }
    }
}

extension CachedSubcellularLocation: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedSubcellularLocation.accession), limit: limit) {
            matches(matchType, text, $0.accession, $0.locationIdentifier, $0.synonyms, $0.keyword)
        }
        return rows
            .map {
                .subcellularLocation(SubcellularLocationOntologyTerm(
                    id: "\(typeKey):\($0.accession)",
                    title: $0.locationIdentifier ?? $0.accession,
                    accession: $0.accession,
                    definition: $0.locationDefinition,
                    synonyms: $0.synonyms,
                    topology: $0.topologyIdentifier,
                    orientation: $0.orientationIdentifier,
                    geneOntology: $0.geneOntology,
                    annotation: $0.annotation,
                    referencesText: $0.referencesText,
                    links: $0.links,
                    source: .offline
                ))
            }
    }
}

extension CachedUnimod: OntologySearchable {
    public static func searchResults(matching text: String, matchType: OntologyMatchType, in context: ModelContext, limit: Int) throws -> [OntologyBrowserResult] {
        let rows = try fetchMatchingInBatches(in: context, sortDescriptor: SortDescriptor(\CachedUnimod.accession), limit: limit) {
            matches(matchType, text, $0.accession, $0.name)
        }
        return rows
            .map {
                let parsed = UnimodAdditionalDataParser.parse($0.additionalData)
                return .unimod(UnimodOntologyTerm(
                    id: "\(typeKey):\($0.accession)",
                    name: $0.name ?? $0.accession,
                    accession: $0.accession,
                    definition: $0.unimodDefinition,
                    deltaMonoMass: parsed.deltaMonoMass,
                    deltaAvgeMass: parsed.deltaAvgeMass,
                    deltaComposition: parsed.deltaComposition,
                    specifications: parsed.specifications,
                    source: .offline
                ))
            }
    }
}
