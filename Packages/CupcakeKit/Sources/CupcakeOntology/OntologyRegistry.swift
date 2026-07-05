import Foundation
import SwiftData

/// The full set of 14 ontology tables + `column-template`/`schema` datasets — one entry per
/// manifest `table.name`, confirmed against a real downloaded `manifest-v0.0.2.json`'s `tables`
/// array. This is what drives both `CupcakeOntologyStore.makeContainer()`'s schema and the
/// "Offline Ontology Data" settings screen's list.
public enum OntologyRegistry {
    public static let allModelTypes: [any PersistentModel.Type] = [
        CachedTissue.self,
        CachedSpecies.self,
        CachedHumanDisease.self,
        CachedSubcellularLocation.self,
        CachedUnimod.self,
        CachedMSUniqueVocabularies.self,
        CachedNCBITaxonomy.self,
        CachedChEBICompound.self,
        CachedMondoDisease.self,
        CachedUberonAnatomy.self,
        CachedCellOntology.self,
        CachedPSIMSOntology.self,
        CachedBTOTerm.self,
        CachedDiseaseOntologyTerm.self,
        CachedColumnTemplate.self,
        CachedSDRFSchema.self,
    ]

    /// Human-readable label per `type_key` — for the settings screen. Order matches the
    /// reference plan's own 14-ontology-table listing, with the two non-ontology datasets last.
    public static let displayNames: [String: String] = [
        "tissue": "Tissue",
        "species": "Species",
        "human_disease": "Human Disease",
        "subcellular_location": "Subcellular Location",
        "unimod": "Unimod (PTMs)",
        "ms_unique_vocabularies": "MS Unique Vocabularies",
        "ncbi_taxonomy": "NCBI Taxonomy",
        "chebi": "ChEBI Compounds",
        "mondo": "MONDO Disease",
        "uberon": "Uberon Anatomy",
        "cell_ontology": "Cell Ontology",
        "psi_ms": "PSI-MS",
        "bto": "BRENDA Tissue Ontology",
        "doid": "Disease Ontology",
        "system": "Column Templates",
        "sdrf": "SDRF Schemas",
    ]

    /// Large tables (`ncbi_taxonomy`: 361MB uncompressed / 2.85M rows; `chebi`: ~15MB
    /// compressed) default to off, matching the plan's "12-on/2-off default" — everything else
    /// is small enough (under a few MB) to default on.
    public static let defaultDisabled: Set<String> = ["ncbi_taxonomy", "chebi"]

    /// Dispatches a manifest table's import to the right concrete `OntologyRowDecodable` type by
    /// its `name` (== `typeKey`) — lets callers (the Settings screen) drive imports generically
    /// off the manifest's own table list without hardcoding a type-per-row switch themselves.
    public static func importTable(_ table: OntologyManifestTable, using service: OntologyImportService) async throws {
        switch table.name {
        case CachedTissue.typeKey: try await service.importTable(CachedTissue.self, table: table)
        case CachedSpecies.typeKey: try await service.importTable(CachedSpecies.self, table: table)
        case CachedHumanDisease.typeKey: try await service.importTable(CachedHumanDisease.self, table: table)
        case CachedSubcellularLocation.typeKey: try await service.importTable(CachedSubcellularLocation.self, table: table)
        case CachedUnimod.typeKey: try await service.importTable(CachedUnimod.self, table: table)
        case CachedMSUniqueVocabularies.typeKey: try await service.importTable(CachedMSUniqueVocabularies.self, table: table)
        case CachedNCBITaxonomy.typeKey: try await service.importTable(CachedNCBITaxonomy.self, table: table)
        case CachedChEBICompound.typeKey: try await service.importTable(CachedChEBICompound.self, table: table)
        case CachedMondoDisease.typeKey: try await service.importTable(CachedMondoDisease.self, table: table)
        case CachedUberonAnatomy.typeKey: try await service.importTable(CachedUberonAnatomy.self, table: table)
        case CachedCellOntology.typeKey: try await service.importTable(CachedCellOntology.self, table: table)
        case CachedPSIMSOntology.typeKey: try await service.importTable(CachedPSIMSOntology.self, table: table)
        case CachedBTOTerm.typeKey: try await service.importTable(CachedBTOTerm.self, table: table)
        case CachedDiseaseOntologyTerm.typeKey: try await service.importTable(CachedDiseaseOntologyTerm.self, table: table)
        case CachedColumnTemplate.typeKey: try await service.importTable(CachedColumnTemplate.self, table: table)
        case CachedSDRFSchema.typeKey: try await service.importTable(CachedSDRFSchema.self, table: table)
        default: throw OntologyReleaseError.tableAssetNotFound(table.name)
        }
    }
}
