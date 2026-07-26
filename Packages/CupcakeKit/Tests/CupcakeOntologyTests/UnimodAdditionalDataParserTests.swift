import Foundation
import Testing

@testable import CupcakeOntology

@Suite("UnimodAdditionalDataParser")
struct UnimodAdditionalDataParserTests {
    // Verbatim excerpt of the real additional_data JSON for UNIMOD:21 (Phospho), confirmed by
    // downloading the live ontology-unimod.sqlite.gz release asset and inspecting the raw row.
    private static let realPhosphoJSON = """
    [
        {"id": "record_id", "description": "21"},
        {"id": "delta_mono_mass", "description": "79.966331"},
        {"id": "delta_avge_mass", "description": "79.9799"},
        {"id": "delta_composition", "description": "H O(3) P"},
        {"id": "spec_1_group", "description": "1,1"},
        {"id": "spec_1_hidden", "description": "0,0"},
        {"id": "spec_1_site", "description": "T,S"},
        {"id": "spec_1_position", "description": "Anywhere,Anywhere"},
        {"id": "spec_1_classification", "description": "Post-translational,Post-translational"},
        {"id": "spec_2_group", "description": "2"},
        {"id": "spec_2_hidden", "description": "0"},
        {"id": "spec_2_site", "description": "Y"},
        {"id": "spec_2_position", "description": "Anywhere"},
        {"id": "spec_2_classification", "description": "Post-translational"},
        {"id": "spec_3_group", "description": "3"},
        {"id": "spec_3_hidden", "description": "1"},
        {"id": "spec_3_site", "description": "D"},
        {"id": "spec_3_position", "description": "Anywhere"},
        {"id": "spec_3_classification", "description": "Post-translational"},
        {"id": "spec_3_misc_notes", "description": "Rare"}
    ]
    """

    @Test("parses top-level mass/composition fields from the real Phospho record")
    func parsesTopLevelFields() {
        let parsed = UnimodAdditionalDataParser.parse(Self.realPhosphoJSON)
        #expect(parsed.deltaMonoMass == "79.966331")
        #expect(parsed.deltaAvgeMass == "79.9799")
        #expect(parsed.deltaComposition == "H O(3) P")
    }

    @Test("groups spec_N_* keys by index into per-specification dictionaries")
    func groupsSpecificationsByIndex() {
        let parsed = UnimodAdditionalDataParser.parse(Self.realPhosphoJSON)
        #expect(parsed.specifications.count == 3)
        #expect(parsed.specifications["1"]?["site"] == "T,S")
        #expect(parsed.specifications["1"]?["position"] == "Anywhere,Anywhere")
        #expect(parsed.specifications["2"]?["site"] == "Y")
        #expect(parsed.specifications["3"]?["hidden"] == "1")
        #expect(parsed.specifications["3"]?["misc_notes"] == "Rare")
    }

    @Test("hidden specs are still present in the parsed output, filtering to non-hidden is a display-layer concern, not the parser's")
    func hiddenSpecsArePreserved() {
        let parsed = UnimodAdditionalDataParser.parse(Self.realPhosphoJSON)
        let nonHidden = parsed.specifications.filter { $0.value["hidden"] != "1" }
        #expect(nonHidden.count == 2)
        #expect(parsed.specifications["3"] != nil)
    }

    @Test("nil or malformed additionalData returns an empty, non-crashing result")
    func handlesNilAndMalformedInput() {
        let nilResult = UnimodAdditionalDataParser.parse(nil)
        #expect(nilResult.specifications.isEmpty)
        #expect(nilResult.deltaMonoMass == nil)

        let malformedResult = UnimodAdditionalDataParser.parse("not json")
        #expect(malformedResult.specifications.isEmpty)
    }
}
