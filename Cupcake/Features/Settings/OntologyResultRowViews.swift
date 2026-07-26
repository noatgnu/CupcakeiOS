import CupcakeModels
import SwiftUI

struct OntologyBadge: View {
    let text: String
    var color: Color = .blue

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct OntologyResultRow: View {
    let result: OntologyBrowserResult

    var body: some View {
        switch result {
        case .simpleTerm(let term):
            SimpleOntologyTermRow(term: term)
        case .taxonomy(let term):
            TaxonomyResultRow(term: term)
        case .chemicalCompound(let term):
            ChemicalCompoundResultRow(term: term)
        case .subcellularLocation(let term):
            SubcellularLocationResultRow(term: term)
        case .unimod(let term):
            UnimodResultRow(term: term)
        }
    }
}

struct OntologyResultDetailView: View {
    let result: OntologyBrowserResult

    var body: some View {
        Form {
            switch result {
            case .simpleTerm(let term):
                SimpleOntologyTermDetailView(term: term)
            case .taxonomy(let term):
                TaxonomyDetailView(term: term)
            case .chemicalCompound(let term):
                ChemicalCompoundDetailView(term: term)
            case .subcellularLocation(let term):
                SubcellularLocationDetailView(term: term)
            case .unimod(let term):
                UnimodDetailView(term: term)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(result.searchTitle)
    }
}

// MARK: - Simple Term (covers 10 of the 14 ontology types)

struct SimpleOntologyTermRow: View {
    let term: SimpleOntologyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.title)
                if let badge = term.badge {
                    OntologyBadge(text: badge)
                }
            }
            if let definition = term.definition, !definition.isEmpty {
                Text(definition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let synonyms = term.synonyms, !synonyms.isEmpty {
                Text("Synonyms: \(synonyms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let accession = term.accession {
                Text(accession)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SimpleOntologyTermDetailView: View {
    let term: SimpleOntologyTerm

    var body: some View {
        Section("Overview") {
            LabeledContent("Name", value: term.title)
            if let accession = term.accession {
                LabeledContent("Accession", value: accession)
            }
            if let badge = term.badge {
                LabeledContent("Type", value: badge)
            }
        }
        if let definition = term.definition, !definition.isEmpty {
            Section("Definition") {
                Text(definition)
            }
        }
        if let synonyms = term.synonyms, !synonyms.isEmpty {
            Section("Synonyms") {
                Text(synonyms)
            }
        }
        if let relatedTerms = term.relatedTerms, !relatedTerms.isEmpty {
            Section("Related Terms") {
                Text(relatedTerms)
            }
        }
    }
}

// MARK: - Taxonomy (NCBI Taxonomy only)

struct TaxonomyResultRow: View {
    let term: TaxonomyOntologyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.scientificName).italic()
                if let rank = term.rank {
                    OntologyBadge(text: rank, color: .purple)
                }
            }
            if let commonName = term.commonName, !commonName.isEmpty {
                Text(commonName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let synonyms = term.synonyms, !synonyms.isEmpty {
                Text("Synonyms: \(synonyms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct TaxonomyDetailView: View {
    let term: TaxonomyOntologyTerm

    var body: some View {
        Section("Overview") {
            LabeledContent("Scientific Name", value: term.scientificName)
            if let commonName = term.commonName {
                LabeledContent("Common Name", value: commonName)
            }
            if let rank = term.rank {
                LabeledContent("Rank", value: rank)
            }
            if let parentTaxId = term.parentTaxId {
                LabeledContent("Parent Taxon ID", value: String(parentTaxId))
            }
        }
        if let synonyms = term.synonyms, !synonyms.isEmpty {
            Section("Synonyms") {
                Text(synonyms)
            }
        }
    }
}

// MARK: - Chemical Compound (ChEBI only)

struct ChemicalCompoundResultRow: View {
    let term: ChemicalCompoundOntologyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(term.name)
            if let definition = term.definition, !definition.isEmpty {
                Text(definition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let synonyms = term.synonyms, !synonyms.isEmpty {
                Text("Synonyms: \(synonyms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let formula = term.formula {
                Text(formula)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ChemicalCompoundDetailView: View {
    let term: ChemicalCompoundOntologyTerm

    var body: some View {
        Section("Overview") {
            LabeledContent("Name", value: term.name)
            if let accession = term.accession {
                LabeledContent("Accession", value: accession)
            }
        }
        if let definition = term.definition, !definition.isEmpty {
            Section("Definition") {
                Text(definition)
            }
        }
        if term.formula != nil || term.mass != nil || term.charge != nil {
            Section("Properties") {
                if let formula = term.formula {
                    LabeledContent("Formula", value: formula)
                }
                if let mass = term.mass {
                    LabeledContent("Mass", value: mass)
                }
                if let charge = term.charge {
                    LabeledContent("Charge", value: String(charge))
                }
            }
        }
        if term.inchi != nil || term.smiles != nil {
            Section("Structure") {
                if let inchi = term.inchi {
                    LabeledContent("InChI") {
                        Text(inchi).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let smiles = term.smiles {
                    LabeledContent("SMILES") {
                        Text(smiles).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }
        if let synonyms = term.synonyms, !synonyms.isEmpty {
            Section("Synonyms") {
                Text(synonyms)
            }
        }
    }
}

// MARK: - Subcellular Location

struct SubcellularLocationResultRow: View {
    let term: SubcellularLocationOntologyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(term.title)
            if let definition = term.definition, !definition.isEmpty {
                Text(definition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let synonyms = term.synonyms, !synonyms.isEmpty {
                Text("Synonyms: \(synonyms)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let accession = term.accession {
                Text(accession)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SubcellularLocationDetailView: View {
    let term: SubcellularLocationOntologyTerm

    var body: some View {
        Section("Overview") {
            LabeledContent("Name", value: term.title)
            if let accession = term.accession {
                LabeledContent("Accession", value: accession)
            }
        }
        if let definition = term.definition, !definition.isEmpty {
            Section("Definition") {
                Text(definition)
            }
        }
        if term.topology != nil || term.orientation != nil {
            Section("Topology") {
                if let topology = term.topology {
                    LabeledContent("Topology", value: topology)
                }
                if let orientation = term.orientation {
                    LabeledContent("Orientation", value: orientation)
                }
            }
        }
        if term.geneOntology != nil || term.links != nil {
            Section("Cross-References") {
                if let geneOntology = term.geneOntology {
                    LabeledContent("Gene Ontology", value: geneOntology)
                }
                if let links = term.links {
                    Text(links).font(.caption)
                }
            }
        }
        if let annotation = term.annotation, !annotation.isEmpty {
            Section("Annotation") {
                Text(annotation)
            }
        }
        if let referencesText = term.referencesText, !referencesText.isEmpty {
            Section("References") {
                Text(referencesText)
            }
        }
        if let synonyms = term.synonyms, !synonyms.isEmpty {
            Section("Synonyms") {
                Text(synonyms)
            }
        }
    }
}

// MARK: - Unimod

struct UnimodResultRow: View {
    let term: UnimodOntologyTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(term.name)
                if let deltaMonoMass = term.deltaMonoMass {
                    OntologyBadge(text: "\u{0394}\(deltaMonoMass)", color: .orange)
                }
            }
            if let definition = term.definition, !definition.isEmpty {
                Text(definition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let accession = term.accession {
                Text(accession)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct UnimodDetailView: View {
    let term: UnimodOntologyTerm

    private var visibleSpecifications: [(key: String, spec: [String: String])] {
        term.specifications
            .filter { $0.value["hidden"] != "1" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, spec: $0.value) }
    }

    var body: some View {
        Section("Overview") {
            LabeledContent("Name", value: term.name)
            if let accession = term.accession {
                LabeledContent("Accession", value: accession)
            }
        }
        if let definition = term.definition, !definition.isEmpty {
            Section("Definition") {
                Text(definition)
            }
        }
        if term.deltaMonoMass != nil || term.deltaAvgeMass != nil || term.deltaComposition != nil {
            Section("Mass") {
                if let deltaMonoMass = term.deltaMonoMass {
                    LabeledContent("Delta Mono Mass", value: deltaMonoMass)
                }
                if let deltaAvgeMass = term.deltaAvgeMass {
                    LabeledContent("Delta Avge Mass", value: deltaAvgeMass)
                }
                if let deltaComposition = term.deltaComposition {
                    LabeledContent("Composition", value: deltaComposition)
                }
            }
        }
        if !visibleSpecifications.isEmpty {
            Section("Specifications") {
                ForEach(visibleSpecifications, id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        if let site = entry.spec["site"], !site.isEmpty {
                            Text("Site: \(site)")
                        }
                        if let position = entry.spec["position"], !position.isEmpty {
                            Text("Position: \(position)").font(.caption).foregroundStyle(.secondary)
                        }
                        if let classification = entry.spec["classification"], !classification.isEmpty {
                            Text("Class: \(classification)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
