import Foundation
import SwiftData


@Model
public final class CachedNCBITaxonomy {
    @Attribute(.unique) public var taxId: Int
    public var scientificName: String?
    public var commonName: String?
    public var synonyms: String?
    public var rank: String?
    public var parentTaxId: Int?

    public init(taxId: Int, scientificName: String? = nil, commonName: String? = nil, synonyms: String? = nil, rank: String? = nil, parentTaxId: Int? = nil) {
        self.taxId = taxId
        self.scientificName = scientificName
        self.commonName = commonName
        self.synonyms = synonyms
        self.rank = rank
        self.parentTaxId = parentTaxId
    }
}

extension CachedNCBITaxonomy: OntologyRowDecodable {
    public static let typeKey = "ncbi_taxonomy"
    public convenience init?(row: [String: String?]) {
        guard let taxIdString = row["tax_id"] ?? nil, let taxId = Int(taxIdString) else { return nil }
        self.init(
            taxId: taxId,
            scientificName: row["scientific_name"] ?? nil,
            commonName: row["common_name"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            rank: row["rank"] ?? nil,
            parentTaxId: (row["parent_tax_id"] ?? nil).flatMap(Int.init)
        )
    }
}

@Model
public final class CachedChEBICompound {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var chebiDefinition: String?
    public var synonyms: String?
    public var formula: String?
    public var mass: String?
    public var charge: Int?
    public var inchi: String?
    public var smiles: String?
    public var parentTerms: String?
    public var roles: String?
    public var replacementTerm: String?

    public init(
        identifier: String,
        name: String? = nil,
        chebiDefinition: String? = nil,
        synonyms: String? = nil,
        formula: String? = nil,
        mass: String? = nil,
        charge: Int? = nil,
        inchi: String? = nil,
        smiles: String? = nil,
        parentTerms: String? = nil,
        roles: String? = nil,
        replacementTerm: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.chebiDefinition = chebiDefinition
        self.synonyms = synonyms
        self.formula = formula
        self.mass = mass
        self.charge = charge
        self.inchi = inchi
        self.smiles = smiles
        self.parentTerms = parentTerms
        self.roles = roles
        self.replacementTerm = replacementTerm
    }
}

extension CachedChEBICompound: OntologyRowDecodable {
    public static let typeKey = "chebi"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            chebiDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            formula: row["formula"] ?? nil,
            mass: row["mass"] ?? nil,
            charge: (row["charge"] ?? nil).flatMap(Int.init),
            inchi: row["inchi"] ?? nil,
            smiles: row["smiles"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            roles: row["roles"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedMondoDisease {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var mondoDefinition: String?
    public var synonyms: String?
    public var xrefs: String?
    public var parentTerms: String?
    public var replacementTerm: String?

    public init(identifier: String, name: String? = nil, mondoDefinition: String? = nil, synonyms: String? = nil, xrefs: String? = nil, parentTerms: String? = nil, replacementTerm: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.mondoDefinition = mondoDefinition
        self.synonyms = synonyms
        self.xrefs = xrefs
        self.parentTerms = parentTerms
        self.replacementTerm = replacementTerm
    }
}

extension CachedMondoDisease: OntologyRowDecodable {
    public static let typeKey = "mondo"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            mondoDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            xrefs: row["xrefs"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedUberonAnatomy {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var uberonDefinition: String?
    public var synonyms: String?
    public var xrefs: String?
    public var parentTerms: String?
    public var partOf: String?
    public var replacementTerm: String?

    public init(
        identifier: String,
        name: String? = nil,
        uberonDefinition: String? = nil,
        synonyms: String? = nil,
        xrefs: String? = nil,
        parentTerms: String? = nil,
        partOf: String? = nil,
        replacementTerm: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.uberonDefinition = uberonDefinition
        self.synonyms = synonyms
        self.xrefs = xrefs
        self.parentTerms = parentTerms
        self.partOf = partOf
        self.replacementTerm = replacementTerm
    }
}

extension CachedUberonAnatomy: OntologyRowDecodable {
    public static let typeKey = "uberon"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            uberonDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            xrefs: row["xrefs"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            partOf: row["part_of"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedCellOntology {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var cellDefinition: String?
    public var synonyms: String?
    public var accession: String?
    public var cellLine: String?
    public var source: String?
    public var parentTerms: String?
    public var partOf: String?
    public var developsFrom: String?
    public var replacementTerm: String?

    public init(
        identifier: String,
        name: String? = nil,
        cellDefinition: String? = nil,
        synonyms: String? = nil,
        accession: String? = nil,
        cellLine: String? = nil,
        source: String? = nil,
        parentTerms: String? = nil,
        partOf: String? = nil,
        developsFrom: String? = nil,
        replacementTerm: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.cellDefinition = cellDefinition
        self.synonyms = synonyms
        self.accession = accession
        self.cellLine = cellLine
        self.source = source
        self.parentTerms = parentTerms
        self.partOf = partOf
        self.developsFrom = developsFrom
        self.replacementTerm = replacementTerm
    }
}

extension CachedCellOntology: OntologyRowDecodable {
    public static let typeKey = "cell_ontology"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            cellDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            accession: row["accession"] ?? nil,
            cellLine: row["cell_line"] ?? nil,
            source: row["source"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            partOf: row["part_of"] ?? nil,
            developsFrom: row["develops_from"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedPSIMSOntology {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var psimsDefinition: String?
    public var synonyms: String?
    public var parentTerms: String?
    public var category: String?
    public var replacementTerm: String?

    public init(identifier: String, name: String? = nil, psimsDefinition: String? = nil, synonyms: String? = nil, parentTerms: String? = nil, category: String? = nil, replacementTerm: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.psimsDefinition = psimsDefinition
        self.synonyms = synonyms
        self.parentTerms = parentTerms
        self.category = category
        self.replacementTerm = replacementTerm
    }
}

extension CachedPSIMSOntology: OntologyRowDecodable {
    public static let typeKey = "psi_ms"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            psimsDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            category: row["category"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedBTOTerm {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var btoDefinition: String?
    public var synonyms: String?
    public var xrefs: String?
    public var parentTerms: String?
    public var partOf: String?
    public var replacementTerm: String?

    public init(
        identifier: String,
        name: String? = nil,
        btoDefinition: String? = nil,
        synonyms: String? = nil,
        xrefs: String? = nil,
        parentTerms: String? = nil,
        partOf: String? = nil,
        replacementTerm: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.btoDefinition = btoDefinition
        self.synonyms = synonyms
        self.xrefs = xrefs
        self.parentTerms = parentTerms
        self.partOf = partOf
        self.replacementTerm = replacementTerm
    }
}

extension CachedBTOTerm: OntologyRowDecodable {
    public static let typeKey = "bto"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            btoDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            xrefs: row["xrefs"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            partOf: row["part_of"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}

@Model
public final class CachedDiseaseOntologyTerm {
    @Attribute(.unique) public var identifier: String
    public var name: String?
    public var doidDefinition: String?
    public var synonyms: String?
    public var xrefs: String?
    public var parentTerms: String?
    public var replacementTerm: String?

    public init(identifier: String, name: String? = nil, doidDefinition: String? = nil, synonyms: String? = nil, xrefs: String? = nil, parentTerms: String? = nil, replacementTerm: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.doidDefinition = doidDefinition
        self.synonyms = synonyms
        self.xrefs = xrefs
        self.parentTerms = parentTerms
        self.replacementTerm = replacementTerm
    }
}

extension CachedDiseaseOntologyTerm: OntologyRowDecodable {
    public static let typeKey = "doid"
    public convenience init?(row: [String: String?]) {
        guard let identifier = row["identifier"] ?? nil else { return nil }
        self.init(
            identifier: identifier,
            name: row["name"] ?? nil,
            doidDefinition: row["definition"] ?? nil,
            synonyms: row["synonyms"] ?? nil,
            xrefs: row["xrefs"] ?? nil,
            parentTerms: row["parent_terms"] ?? nil,
            replacementTerm: row["replacement_term"] ?? nil
        )
    }
}
