import Foundation
import SwiftData

// Ontology reference data lives in its own `CupcakeOntologyStore` container, read-only and independently rebuildable per table.

/// `identifier, accession, synonyms, cross_references`.
@Model
public final class CachedTissue {
    @Attribute(.unique) public var identifier: String
    public var accession: String?
    public var synonyms: String?
    public var crossReferences: String?

    public init(identifier: String, accession: String? = nil, synonyms: String? = nil, crossReferences: String? = nil) {
        self.identifier = identifier
        self.accession = accession
        self.synonyms = synonyms
        self.crossReferences = crossReferences
    }
}

extension CachedTissue: OntologyRowDecodable {
    public static let typeKey = "tissue"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(identifier: identifier, accession: row["accession"] ?? nil, synonyms: row["synonyms"] ?? nil, crossReferences: row["cross_references"] ?? nil)
    }
}

/// `id, code, taxon, official_name, common_name, synonym` — `code` is this table's natural unique key.
@Model
public final class CachedSpecies {
    @Attribute(.unique) public var code: String
    public var taxon: Int?
    public var officialName: String?
    public var commonName: String?
    public var synonym: String?

    public init(code: String, taxon: Int? = nil, officialName: String? = nil, commonName: String? = nil, synonym: String? = nil) {
        self.code = code
        self.taxon = taxon
        self.officialName = officialName
        self.commonName = commonName
        self.synonym = synonym
    }
}

extension CachedSpecies: OntologyRowDecodable {
    public static let typeKey = "species"
    public convenience init?(row: [String: String?]) {
        guard let code = row["code"] ?? nil else { return nil }
        self.init(
            code: code,
            taxon: (row["taxon"] ?? nil).flatMap(Int.init),
            officialName: row["official_name"] ?? nil,
            commonName: row["common_name"] ?? nil,
            synonym: row["synonym"] ?? nil
        )
    }
}

/// `identifier, acronym, accession, definition, synonyms, cross_references, keywords`.
@Model
public final class CachedHumanDisease {
    @Attribute(.unique) public var identifier: String
    public var acronym: String?
    public var accession: String?
    public var diseaseDefinition: String?
    public var synonyms: String?
    public var crossReferences: String?
    public var keywords: String?

    public init(identifier: String, acronym: String? = nil, accession: String? = nil, diseaseDefinition: String? = nil, synonyms: String? = nil, crossReferences: String? = nil, keywords: String? = nil) {
        self.identifier = identifier
        self.acronym = acronym
        self.accession = accession
        self.diseaseDefinition = diseaseDefinition
        self.synonyms = synonyms
        self.crossReferences = crossReferences
        self.keywords = keywords
    }
}

extension CachedHumanDisease: OntologyRowDecodable {
    public static let typeKey = "human_disease"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            acronym: row["acronym"] ?? nil,
            accession: row["accession"] ?? nil,
            diseaseDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            crossReferences: row["cross_references"] ?? nil,
            keywords: row["keywords"] ?? nil
        )
    }
}

/// `location_identifier, topology_identifier, ..., accession, ...`. `accession` is this table's unique key.
@Model
public final class CachedSubcellularLocation {
    @Attribute(.unique) public var accession: String
    public var locationIdentifier: String?
    public var topologyIdentifier: String?
    public var orientationIdentifier: String?
    public var locationDefinition: String?
    public var synonyms: String?
    public var content: String?
    public var isA: String?
    public var partOf: String?
    public var keyword: String?
    public var geneOntology: String?
    public var annotation: String?
    public var referencesText: String?
    public var links: String?

    public init(
        accession: String,
        locationIdentifier: String? = nil,
        topologyIdentifier: String? = nil,
        orientationIdentifier: String? = nil,
        locationDefinition: String? = nil,
        synonyms: String? = nil,
        content: String? = nil,
        isA: String? = nil,
        partOf: String? = nil,
        keyword: String? = nil,
        geneOntology: String? = nil,
        annotation: String? = nil,
        referencesText: String? = nil,
        links: String? = nil
    ) {
        self.accession = accession
        self.locationIdentifier = locationIdentifier
        self.topologyIdentifier = topologyIdentifier
        self.orientationIdentifier = orientationIdentifier
        self.locationDefinition = locationDefinition
        self.synonyms = synonyms
        self.content = content
        self.isA = isA
        self.partOf = partOf
        self.keyword = keyword
        self.geneOntology = geneOntology
        self.annotation = annotation
        self.referencesText = referencesText
        self.links = links
    }
}

extension CachedSubcellularLocation: OntologyRowDecodable {
    public static let typeKey = "subcellular_location"
    public convenience init?(row: [String: String?]) {
        guard let accession = row["accession"] ?? nil else { return nil }
        self.init(
            accession: accession,
            locationIdentifier: row["location_identifier"] ?? nil,
            topologyIdentifier: row["topology_identifier"] ?? nil,
            orientationIdentifier: row["orientation_identifier"] ?? nil,
            locationDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            content: row["content"] ?? nil,
            isA: row["is_a"] ?? nil,
            partOf: row["part_of"] ?? nil,
            keyword: row["keyword"] ?? nil,
            geneOntology: row["gene_ontology"] ?? nil,
            annotation: row["annotation"] ?? nil,
            referencesText: row["references"] ?? nil,
            links: row["links"] ?? nil
        )
    }
}

/// `accession, name, definition, additional_data` — `additional_data` is JSON, kept as raw text.
@Model
public final class CachedUnimod {
    @Attribute(.unique) public var accession: String
    public var name: String?
    public var unimodDefinition: String?
    public var additionalData: String?

    public init(accession: String, name: String? = nil, unimodDefinition: String? = nil, additionalData: String? = nil) {
        self.accession = accession
        self.name = name
        self.unimodDefinition = unimodDefinition
        self.additionalData = additionalData
    }
}

extension CachedUnimod: OntologyRowDecodable {
    public static let typeKey = "unimod"
    public convenience init?(row: [String: String?]) {
        guard let accession = row["accession"] ?? nil else { return nil }
        self.init(accession: accession, name: row["name"] ?? nil, unimodDefinition: row["definition"] ?? nil, additionalData: row["additional_data"] ?? nil)
    }
}

/// `accession, name, definition, term_type`.
@Model
public final class CachedMSUniqueVocabularies {
    @Attribute(.unique) public var accession: String
    public var name: String?
    public var vocabularyDefinition: String?
    public var termType: String?

    public init(accession: String, name: String? = nil, vocabularyDefinition: String? = nil, termType: String? = nil) {
        self.accession = accession
        self.name = name
        self.vocabularyDefinition = vocabularyDefinition
        self.termType = termType
    }
}

extension CachedMSUniqueVocabularies: OntologyRowDecodable {
    public static let typeKey = "ms_unique_vocabularies"
    public convenience init?(row: [String: String?]) {
        guard let accession = row["accession"] ?? nil else { return nil }
        self.init(accession: accession, name: row["name"] ?? nil, vocabularyDefinition: row["definition"] ?? nil, termType: row["term_type"] ?? nil)
    }
}

/// Tracks what's actually been imported, independent of the manifest describing what's available.
@Model
public final class OntologyImportState {
    @Attribute(.unique) public var typeKey: String
    public var isEnabled: Bool
    public var importedAt: Date?
    public var rowCount: Int?

    public init(typeKey: String, isEnabled: Bool = false, importedAt: Date? = nil, rowCount: Int? = nil) {
        self.typeKey = typeKey
        self.isEnabled = isEnabled
        self.importedAt = importedAt
        self.rowCount = rowCount
    }
}
