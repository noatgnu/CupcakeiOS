import Foundation

public enum OntologyResultSource: String, Sendable {
    case offline
    case online
}

public enum OntologyMatchType: String, CaseIterable, Identifiable, Sendable {
    case contains
    case startsWith = "startswith"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .contains: "Contains"
        case .startsWith: "Starts With"
        }
    }

    public func matches(_ field: String?, _ text: String) -> Bool {
        guard let field else { return false }
        switch self {
        case .contains:
            return field.localizedCaseInsensitiveContains(text)
        case .startsWith:
            return field.range(of: text, options: [.caseInsensitive, .anchored]) != nil
        }
    }
}

public struct SimpleOntologyTerm: Identifiable, Sendable {
    public let id: String
    public let typeKey: String
    public let title: String
    public let accession: String?
    public let definition: String?
    public let synonyms: String?
    public let relatedTerms: String?
    public let badge: String?
    public let source: OntologyResultSource

    public init(
        id: String,
        typeKey: String,
        title: String,
        accession: String? = nil,
        definition: String? = nil,
        synonyms: String? = nil,
        relatedTerms: String? = nil,
        badge: String? = nil,
        source: OntologyResultSource
    ) {
        self.id = id
        self.typeKey = typeKey
        self.title = title
        self.accession = accession
        self.definition = definition
        self.synonyms = synonyms
        self.relatedTerms = relatedTerms
        self.badge = badge
        self.source = source
    }
}

public struct TaxonomyOntologyTerm: Identifiable, Sendable {
    public let id: String
    public let typeKey: String
    public let scientificName: String
    public let commonName: String?
    public let synonyms: String?
    public let rank: String?
    public let parentTaxId: Int?
    public let source: OntologyResultSource

    public init(
        id: String,
        typeKey: String = "ncbi_taxonomy",
        scientificName: String,
        commonName: String? = nil,
        synonyms: String? = nil,
        rank: String? = nil,
        parentTaxId: Int? = nil,
        source: OntologyResultSource
    ) {
        self.id = id
        self.typeKey = typeKey
        self.scientificName = scientificName
        self.commonName = commonName
        self.synonyms = synonyms
        self.rank = rank
        self.parentTaxId = parentTaxId
        self.source = source
    }
}

public struct ChemicalCompoundOntologyTerm: Identifiable, Sendable {
    public let id: String
    public let typeKey: String
    public let name: String
    public let accession: String?
    public let definition: String?
    public let synonyms: String?
    public let formula: String?
    public let mass: String?
    public let charge: Int?
    public let inchi: String?
    public let smiles: String?
    public let source: OntologyResultSource

    public init(
        id: String,
        typeKey: String = "chebi",
        name: String,
        accession: String? = nil,
        definition: String? = nil,
        synonyms: String? = nil,
        formula: String? = nil,
        mass: String? = nil,
        charge: Int? = nil,
        inchi: String? = nil,
        smiles: String? = nil,
        source: OntologyResultSource
    ) {
        self.id = id
        self.typeKey = typeKey
        self.name = name
        self.accession = accession
        self.definition = definition
        self.synonyms = synonyms
        self.formula = formula
        self.mass = mass
        self.charge = charge
        self.inchi = inchi
        self.smiles = smiles
        self.source = source
    }
}

public struct SubcellularLocationOntologyTerm: Identifiable, Sendable {
    public let id: String
    public let typeKey: String
    public let title: String
    public let accession: String?
    public let definition: String?
    public let synonyms: String?
    public let topology: String?
    public let orientation: String?
    public let geneOntology: String?
    public let annotation: String?
    public let referencesText: String?
    public let links: String?
    public let source: OntologyResultSource

    public init(
        id: String,
        typeKey: String = "subcellular_location",
        title: String,
        accession: String? = nil,
        definition: String? = nil,
        synonyms: String? = nil,
        topology: String? = nil,
        orientation: String? = nil,
        geneOntology: String? = nil,
        annotation: String? = nil,
        referencesText: String? = nil,
        links: String? = nil,
        source: OntologyResultSource
    ) {
        self.id = id
        self.typeKey = typeKey
        self.title = title
        self.accession = accession
        self.definition = definition
        self.synonyms = synonyms
        self.topology = topology
        self.orientation = orientation
        self.geneOntology = geneOntology
        self.annotation = annotation
        self.referencesText = referencesText
        self.links = links
        self.source = source
    }
}

public struct UnimodOntologyTerm: Identifiable, Sendable {
    public let id: String
    public let typeKey: String
    public let name: String
    public let accession: String?
    public let definition: String?
    public let deltaMonoMass: String?
    public let deltaAvgeMass: String?
    public let deltaComposition: String?
    public let specifications: [String: [String: String]]
    public let source: OntologyResultSource

    public init(
        id: String,
        typeKey: String = "unimod",
        name: String,
        accession: String? = nil,
        definition: String? = nil,
        deltaMonoMass: String? = nil,
        deltaAvgeMass: String? = nil,
        deltaComposition: String? = nil,
        specifications: [String: [String: String]] = [:],
        source: OntologyResultSource
    ) {
        self.id = id
        self.typeKey = typeKey
        self.name = name
        self.accession = accession
        self.definition = definition
        self.deltaMonoMass = deltaMonoMass
        self.deltaAvgeMass = deltaAvgeMass
        self.deltaComposition = deltaComposition
        self.specifications = specifications
        self.source = source
    }
}

public enum OntologyBrowserResult: Identifiable, Sendable {
    case simpleTerm(SimpleOntologyTerm)
    case taxonomy(TaxonomyOntologyTerm)
    case chemicalCompound(ChemicalCompoundOntologyTerm)
    case subcellularLocation(SubcellularLocationOntologyTerm)
    case unimod(UnimodOntologyTerm)

    public var id: String {
        switch self {
        case .simpleTerm(let term): term.id
        case .taxonomy(let term): term.id
        case .chemicalCompound(let term): term.id
        case .subcellularLocation(let term): term.id
        case .unimod(let term): term.id
        }
    }

    public var typeKey: String {
        switch self {
        case .simpleTerm(let term): term.typeKey
        case .taxonomy(let term): term.typeKey
        case .chemicalCompound(let term): term.typeKey
        case .subcellularLocation(let term): term.typeKey
        case .unimod(let term): term.typeKey
        }
    }

    public var searchTitle: String {
        switch self {
        case .simpleTerm(let term): term.title
        case .taxonomy(let term): term.scientificName
        case .chemicalCompound(let term): term.name
        case .subcellularLocation(let term): term.title
        case .unimod(let term): term.name
        }
    }
}
