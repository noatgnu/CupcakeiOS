import Testing

@testable import CupcakeModels

@Suite("SDRF special syntax")
struct SDRFSpecialSyntaxTests {
    @Test("detects age by column name")
    func detectsAge() {
        #expect(SDRFSyntaxDetector.detect(columnName: "characteristics[age]", columnType: "characteristics") == .age)
    }

    @Test("detects modification by column name")
    func detectsModification() {
        #expect(SDRFSyntaxDetector.detect(columnName: "comment[modification parameters]", columnType: "comment") == .modification)
    }

    @Test("detects cleavage by column name")
    func detectsCleavage() {
        #expect(SDRFSyntaxDetector.detect(columnName: "comment[cleavage agent details]", columnType: "comment") == .cleavage)
    }

    @Test("detects spiked compound by column name")
    func detectsSpikedCompound() {
        #expect(SDRFSyntaxDetector.detect(columnName: "characteristics[spiked compound]", columnType: "characteristics") == .spikedCompound)
    }

    @Test("returns nil for an ordinary column")
    func detectsNil() {
        #expect(SDRFSyntaxDetector.detect(columnName: "Serial Number", columnType: "characteristics") == nil)
    }

    @Test("parses and formats modification key-value syntax round-trip")
    func modificationRoundTrip() {
        let raw = "NT=Oxidation;AC=UNIMOD:35;MT=Variable;TA=M"
        let fields = SDRFKeyValueSyntax.parse(raw, allowedKeys: SDRFModificationKeys.order)
        #expect(fields["NT"] == "Oxidation")
        #expect(fields["AC"] == "UNIMOD:35")
        #expect(fields["MT"] == "Variable")
        #expect(fields["TA"] == "M")

        let formatted = SDRFKeyValueSyntax.format(fields, keyOrder: SDRFModificationKeys.order)
        #expect(formatted == "NT=Oxidation;AC=UNIMOD:35;MT=Variable;TA=M")
    }

    @Test("parse ignores keys not in the allowed list")
    func parseIgnoresUnknownKeys() {
        let fields = SDRFKeyValueSyntax.parse("NT=Test;XX=Ignored", allowedKeys: SDRFCleavageKeys.order)
        #expect(fields["NT"] == "Test")
        #expect(fields["XX"] == nil)
    }

    @Test("format skips empty values")
    func formatSkipsEmptyValues() {
        let formatted = SDRFKeyValueSyntax.format(["NT": "Trypsin", "AC": ""], keyOrder: SDRFCleavageKeys.order)
        #expect(formatted == "NT=Trypsin")
    }

    @Test("parses a valid age string")
    func parsesAge() {
        let parsed = SDRFAgeSyntax.parse("25Y3M15D")
        #expect(parsed?.years == "25")
        #expect(parsed?.months == "3")
        #expect(parsed?.days == "15")
    }

    @Test("returns nil for an invalid age string")
    func parsesInvalidAge() {
        #expect(SDRFAgeSyntax.parse("not an age") == nil)
    }

    @Test("formats age components, defaulting empty fields to 0")
    func formatsAge() {
        #expect(SDRFAgeSyntax.format(years: "25", months: "3", days: "15") == "25Y3M15D")
        #expect(SDRFAgeSyntax.format(years: "", months: "", days: "") == "0Y0M0D")
    }
}
