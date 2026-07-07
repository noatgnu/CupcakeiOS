import Testing

@testable import CupcakeTranscription

@Suite("AudioRecorder")
struct AudioRecorderTests {
    @Test("normalizedLevel maps -60dB...0dB onto 0...1")
    func normalizedLevelMapsRange() {
        #expect(AudioRecorder.normalizedLevel(decibels: -60) == 0)
        #expect(AudioRecorder.normalizedLevel(decibels: 0) == 1)
        #expect(AudioRecorder.normalizedLevel(decibels: -30) == 0.5)
    }

    @Test("normalizedLevel clamps below -60dB and non-finite values to 0")
    func normalizedLevelClampsQuiet() {
        #expect(AudioRecorder.normalizedLevel(decibels: -120) == 0)
        #expect(AudioRecorder.normalizedLevel(decibels: -.infinity) == 0)
    }
}
