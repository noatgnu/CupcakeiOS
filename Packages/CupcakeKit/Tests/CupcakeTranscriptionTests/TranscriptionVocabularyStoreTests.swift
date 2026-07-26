import Foundation
import Testing

@testable import CupcakeTranscription

@Suite("TranscriptionVocabularyStore")
struct TranscriptionVocabularyStoreTests {
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "TranscriptionVocabularyStoreTests-\(UUID().uuidString)")!
        return defaults
    }

    @Test("add appends a trimmed term, empty/whitespace-only text is ignored")
    func addAppendsTrimmedTerm() {
        let defaults = makeDefaults()
        TranscriptionVocabularyStore.add("  cryo-EM  ", defaults: defaults)
        TranscriptionVocabularyStore.add("   ", defaults: defaults)
        TranscriptionVocabularyStore.add("", defaults: defaults)

        let terms = TranscriptionVocabularyStore.allTerms(defaults: defaults)
        #expect(terms.count == 1)
        #expect(terms.first?.text == "cryo-EM")
    }

    @Test("remove deletes the matching term by id, leaves others untouched")
    func removeDeletesMatchingTerm() throws {
        let defaults = makeDefaults()
        TranscriptionVocabularyStore.add("Rab10 GTPase", defaults: defaults)
        TranscriptionVocabularyStore.add("MST3 kinase", defaults: defaults)
        let terms = TranscriptionVocabularyStore.allTerms(defaults: defaults)
        let idToRemove = try #require(terms.first(where: { $0.text == "Rab10 GTPase" })?.id)

        TranscriptionVocabularyStore.remove(id: idToRemove, defaults: defaults)

        let remaining = TranscriptionVocabularyStore.allTerms(defaults: defaults)
        #expect(remaining.count == 1)
        #expect(remaining.first?.text == "MST3 kinase")
    }

    @Test("currentTexts maps stored terms to plain strings in insertion order")
    func currentTextsMapsToStrings() {
        let defaults = makeDefaults()
        TranscriptionVocabularyStore.add("Ni-agarose", defaults: defaults)
        TranscriptionVocabularyStore.add("SEC buffer", defaults: defaults)

        #expect(TranscriptionVocabularyStore.currentTexts(defaults: defaults) == ["Ni-agarose", "SEC buffer"])
    }

    @Test("allTerms returns an empty array when nothing has been stored yet")
    func allTermsEmptyByDefault() {
        let defaults = makeDefaults()
        #expect(TranscriptionVocabularyStore.allTerms(defaults: defaults).isEmpty)
    }
}
