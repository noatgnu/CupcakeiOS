import CupcakeModels
import CupcakeNetworking
import Foundation

public actor OnlineOntologySearchService {
    private let metadataColumnSync: MetadataColumnSyncService

    public init(metadataColumnSync: MetadataColumnSyncService) {
        self.metadataColumnSync = metadataColumnSync
    }

    public func search(text: String, enabledTypeKeys: Set<String>, matchType: OntologyMatchType = .contains, limitPerType: Int = 25) async -> [String: [OntologyBrowserResult]] {
        guard text.count >= 2 else { return [:] }
        return await withTaskGroup(of: (String, [OntologyBrowserResult]).self) { group in
            for typeKey in enabledTypeKeys {
                group.addTask {
                    let dtos = (try? await self.metadataColumnSync.fetchOntologySuggestions(
                        ontologyType: typeKey,
                        customFilters: nil,
                        search: text,
                        limit: limitPerType,
                        match: matchType.rawValue
                    )) ?? []
                    return (typeKey, dtos.map { Self.map($0, typeKey: typeKey) })
                }
            }
            var buckets: [String: [OntologyBrowserResult]] = [:]
            for await (typeKey, results) in group where !results.isEmpty {
                buckets[typeKey] = results
            }
            return buckets
        }
    }

    private static func map(_ dto: OntologySuggestionDTO, typeKey: String) -> OntologyBrowserResult {
        let id = "\(typeKey):\(dto.id)"
        switch typeKey {
        case "unimod":
            let fullData = dto.fullData
            return .unimod(UnimodOntologyTerm(
                id: id,
                name: fullData?.name ?? dto.displayName,
                accession: fullData?.accession ?? dto.value,
                definition: fullData?.definition ?? dto.description,
                deltaMonoMass: fullData?.deltaMonoMass,
                deltaComposition: fullData?.deltaComposition,
                specifications: fullData?.specifications ?? [:],
                source: .online
            ))
        case "ncbi_taxonomy":
            return .taxonomy(TaxonomyOntologyTerm(
                id: id,
                scientificName: dto.displayName,
                commonName: dto.description,
                source: .online
            ))
        case "chebi":
            return .chemicalCompound(ChemicalCompoundOntologyTerm(
                id: id,
                name: dto.displayName,
                accession: dto.value,
                definition: dto.description,
                source: .online
            ))
        case "subcellular_location":
            return .subcellularLocation(SubcellularLocationOntologyTerm(
                id: id,
                title: dto.displayName,
                accession: dto.value,
                definition: dto.description,
                source: .online
            ))
        default:
            return .simpleTerm(SimpleOntologyTerm(
                id: id,
                typeKey: typeKey,
                title: dto.displayName,
                accession: dto.value,
                definition: dto.description,
                source: .online
            ))
        }
    }
}
