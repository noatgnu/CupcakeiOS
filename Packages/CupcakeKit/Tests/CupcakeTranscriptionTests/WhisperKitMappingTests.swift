import Foundation
import Testing

@testable import CupcakeTranscription

@Suite("WhisperKitMapping")
struct WhisperKitMappingTests {
    @Test("whisperLanguageCode derives a bare 2-letter code from a full locale identifier")
    func whisperLanguageCodeDerivesBareCode() {
        #expect(WhisperKitMapping.whisperLanguageCode(from: "en-US") == "en")
        #expect(WhisperKitMapping.whisperLanguageCode(from: "es-ES") == "es")
        #expect(WhisperKitMapping.whisperLanguageCode(from: "zh-Hans") == "zh")
    }

    @Test("makeSegment maps WhisperKit's start/end seconds into timestamp/duration")
    func makeSegmentMapsTiming() {
        let segment = WhisperKitMapping.makeSegment(text: "hello", start: 1.5, end: 3.0)
        #expect(segment.text == "hello")
        #expect(segment.timestamp == 1.5)
        #expect(segment.duration == 1.5)
    }

    @Test("glossaryPrompt returns nil for empty vocabulary, a formatted glossary string otherwise")
    func glossaryPromptFormatsVocabulary() {
        #expect(WhisperKitMapping.glossaryPrompt(vocabulary: []) == nil)
        #expect(
            WhisperKitMapping.glossaryPrompt(vocabulary: ["cryo-EM", "Rab10 GTPase"])
                == "Glossary: cryo-EM, Rab10 GTPase"
        )
    }

    @Test("stripSpecialTokens removes literal Whisper control/timestamp tokens, leaving only real words")
    func stripSpecialTokensRemovesControlTokens() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|0.00|> This is a LRRK2 experiment.<|3.46|><|endoftext|>"
        #expect(WhisperKitMapping.stripSpecialTokens(from: raw) == "This is a LRRK2 experiment.")
        #expect(WhisperKitMapping.stripSpecialTokens(from: "plain text, no tokens") == "plain text, no tokens")
    }

    @Test("makeSegment strips special tokens from the segment text before wrapping it")
    func makeSegmentStripsSpecialTokens() {
        let segment = WhisperKitMapping.makeSegment(text: "<|0.00|> hello<|1.00|>", start: 0, end: 1)
        #expect(segment.text == "hello")
    }
}

@Suite("TranscriptionEngineKind")
struct TranscriptionEngineKindTests {
    @Test("selectedEngineKind defaults to Apple, persists a chosen kind, and falls back to Apple for garbage")
    func selectedEngineKindPersistence() {
        let defaultsSuiteName = "TranscriptionEngineKindTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        #expect(TranscriptionEngineKind(rawValue: "apple") == .apple)
        #expect(TranscriptionEngineKind(rawValue: "whisperKit") == .whisperKit)
        #expect(TranscriptionEngineKind(rawValue: "nonsense") == nil)
    }

    @Test("makeEngine returns the Apple engine for .apple and a WhisperKit engine for .whisperKit")
    func makeEngineReturnsMatchingConformance() {
        #expect(TranscriptionEngineFactory.makeEngine(kind: .apple) is AppleSpeechTranscriptionEngine)
        #expect(TranscriptionEngineFactory.makeEngine(kind: .whisperKit) is WhisperKitTranscriptionEngine)
    }
}
