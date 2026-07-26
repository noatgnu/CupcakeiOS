import Foundation
@preconcurrency import WhisperKit

public actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    private let modelVariant: String
    private nonisolated(unsafe) var cachedPipe: WhisperKit?
    private static let maxPromptTokens = 224

    public init(modelVariant: String) {
        self.modelVariant = modelVariant
    }

    public nonisolated func supportsOnDeviceRecognition(languageCode: String) -> Bool {
        true
    }

    public func transcribe(fileURL: URL, languageCode: String, vocabulary: [String]) async throws -> TranscriptionResult {
        let pipe = try await loadedPipe()
        let audioFileURL = try await AudioTrackExtractor.extractAudioTrack(from: fileURL)

        var options = DecodingOptions()
        options.task = .transcribe
        options.language = WhisperKitMapping.whisperLanguageCode(from: languageCode)

        if let glossary = WhisperKitMapping.glossaryPrompt(vocabulary: vocabulary), let tokenizer = pipe.tokenizer {
            let encoded = tokenizer.encode(text: glossary)
            let specialTokenBegin = tokenizer.specialTokens.specialTokenBegin
            let promptTokens = Array(encoded.filter { $0 < specialTokenBegin }.prefix(Self.maxPromptTokens))
            if !promptTokens.isEmpty {
                options.promptTokens = promptTokens
                options.usePrefillPrompt = true
            }
        }

        let results = try await pipe.transcribe(audioPath: audioFileURL.path, decodeOptions: options)

        let segments = results.flatMap { result in
            result.segments.map { segment in
                WhisperKitMapping.makeSegment(text: segment.text, start: segment.start, end: segment.end)
            }
        }
        let text = WhisperKitMapping.stripSpecialTokens(from: results.map(\.text).joined(separator: " "))

        return TranscriptionResult(
            text: text,
            languageCode: languageCode,
            isOnDevice: true,
            segments: segments
        )
    }

    private func loadedPipe() async throws -> WhisperKit {
        if let cachedPipe { return cachedPipe }
        let pipe = try await WhisperKit(WhisperKitConfig(model: modelVariant, load: true))
        cachedPipe = pipe
        return pipe
    }
}
