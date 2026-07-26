import Foundation

public protocol TranscriptionEngine: Sendable {
    func supportsOnDeviceRecognition(languageCode: String) -> Bool
    func transcribe(fileURL: URL, languageCode: String, vocabulary: [String]) async throws -> TranscriptionResult
}
