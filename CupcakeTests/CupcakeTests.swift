import AVFoundation
import CupcakeTranscription
import Testing

struct CupcakeTests {
    @Test func example() async throws {}

    @Test("On-device transcription round-trips real synthesized speech")
    func transcribesRealSynthesizedSpeech() async throws {
        let phrase = "The gloves are on and the sample is ready."
        let fileURL = try await synthesize(phrase, voiceLanguage: "en-US")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await SpeechTranscriber.transcribe(fileURL: fileURL, localeIdentifier: "en-US")
        let transcript = result.text.lowercased()

        #expect(transcript.contains("gloves"))
        #expect(transcript.contains("sample"))
    }

    private func synthesize(_ text: String, voiceLanguage: String) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)

        var audioFile: AVAudioFile?
        var hasResumed = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            synthesizer.write(utterance) { buffer in
                guard !hasResumed, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                if pcmBuffer.frameLength == 0 {
                    hasResumed = true
                    continuation.resume()
                    return
                }
                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: pcmBuffer.format.settings)
                    }
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
        return outputURL
    }
}
