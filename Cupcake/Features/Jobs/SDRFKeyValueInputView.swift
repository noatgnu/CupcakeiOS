import SwiftUI

struct SDRFKeyValueFieldSpec {
    let key: String
    let label: String
    let options: [String]?

    init(_ key: String, _ label: String, options: [String]? = nil) {
        self.key = key
        self.label = label
        self.options = options
    }
}

struct SDRFKeyValueInputView: View {
    let fieldSpecs: [SDRFKeyValueFieldSpec]
    @Binding var fields: [String: String]
    var onFieldChange: ((String, String) -> Void)?

    var body: some View {
        ForEach(fieldSpecs, id: \.key) { spec in
            if let options = spec.options {
                Picker(spec.label, selection: Binding(
                    get: { fields[spec.key] ?? "" },
                    set: { fields[spec.key] = $0 }
                )) {
                    Text("None").tag("")
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } else {
                TextField(spec.label, text: Binding(
                    get: { fields[spec.key] ?? "" },
                    set: {
                        fields[spec.key] = $0
                        onFieldChange?(spec.key, $0)
                    }
                ))
                .accessibilityIdentifier("sdrfField_\(spec.key)")
            }
        }
    }
}

enum SDRFModificationFieldSpecs {
    static let all: [SDRFKeyValueFieldSpec] = [
        SDRFKeyValueFieldSpec("NT", "Name of Term"),
        SDRFKeyValueFieldSpec("AC", "Accession"),
        SDRFKeyValueFieldSpec("CF", "Chemical Formula"),
        SDRFKeyValueFieldSpec("MT", "Modification Type", options: ["Fixed", "Variable", "Annotated"]),
        SDRFKeyValueFieldSpec("PP", "Position in Polypeptide", options: ["Anywhere", "Protein N-term", "Protein C-term", "Any N-term", "Any C-term"]),
        SDRFKeyValueFieldSpec("TA", "Target Amino Acid"),
        SDRFKeyValueFieldSpec("MM", "Monoisotopic Mass"),
        SDRFKeyValueFieldSpec("TS", "Target Site"),
    ]
}

enum SDRFCleavageFieldSpecs {
    static let all: [SDRFKeyValueFieldSpec] = [
        SDRFKeyValueFieldSpec("NT", "Name of Term"),
        SDRFKeyValueFieldSpec("AC", "Accession"),
        SDRFKeyValueFieldSpec("CS", "Cleavage Site"),
    ]
}

enum SDRFSpikedCompoundFieldSpecs {
    static let all: [SDRFKeyValueFieldSpec] = [
        SDRFKeyValueFieldSpec("SP", "Spiked Compound"),
        SDRFKeyValueFieldSpec("CT", "Compound Type"),
        SDRFKeyValueFieldSpec("QY", "Quantity"),
        SDRFKeyValueFieldSpec("PS", "Purity Score"),
        SDRFKeyValueFieldSpec("AC", "Accession"),
        SDRFKeyValueFieldSpec("CN", "Compound Name"),
        SDRFKeyValueFieldSpec("CV", "Compound Vendor"),
        SDRFKeyValueFieldSpec("CS", "Compound Solvent"),
        SDRFKeyValueFieldSpec("CF", "Compound Formula"),
    ]
}
