import Foundation
import Speech

public struct TranscriptionSegment: Sendable {
    public let text: String
    public let timestamp: TimeInterval
    public let duration: TimeInterval
}

public struct TranscriptionResult: Sendable {
    public let text: String
    public let languageCode: String
    public let isOnDevice: Bool
    public let segments: [TranscriptionSegment]
}

public enum SpeechTranscriptionError: Error {
    case authorizationDenied
    case recognizerUnavailable
}

public enum SpeechTranscriber {
    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public static func supportsOnDeviceRecognition(localeIdentifier: String = Locale.current.identifier) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    public static func transcribe(fileURL: URL, localeIdentifier: String = Locale.current.identifier, vocabulary: [String] = []) async throws -> TranscriptionResult {
        guard await requestAuthorization() else {
            throw SpeechTranscriptionError.authorizationDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        if !vocabulary.isEmpty {
            request.contextualStrings = vocabulary
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                hasResumed = true
                let segments = result.bestTranscription.segments.map {
                    TranscriptionSegment(text: $0.substring, timestamp: $0.timestamp, duration: $0.duration)
                }
                continuation.resume(returning: TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    languageCode: localeIdentifier,
                    isOnDevice: request.requiresOnDeviceRecognition,
                    segments: segments
                ))
            }
        }
    }
}
