import Foundation

public struct AppleSpeechTranscriptionEngine: TranscriptionEngine {
    public init() {}

    public func supportsOnDeviceRecognition(languageCode: String) -> Bool {
        SpeechTranscriber.supportsOnDeviceRecognition(localeIdentifier: languageCode)
    }

    public func transcribe(fileURL: URL, languageCode: String, vocabulary: [String]) async throws -> TranscriptionResult {
        try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: languageCode, vocabulary: vocabulary)
    }
}
