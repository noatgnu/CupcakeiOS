import Testing

@testable import CupcakeTranscription

@Suite("WebVTTFormatter")
struct WebVTTFormatterTests {
    @Test("format produces a valid WEBVTT header and a single cue for one short sentence")
    func formatSingleSentence() {
        let segments = [
            TranscriptionSegment(text: "Gloves", timestamp: 0.0, duration: 0.4),
            TranscriptionSegment(text: "are", timestamp: 0.4, duration: 0.2),
            TranscriptionSegment(text: "on.", timestamp: 0.6, duration: 0.3),
        ]
        let vtt = WebVTTFormatter.format(segments: segments)
        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("00:00:00.000 --> 00:00:00.900"))
        #expect(vtt.contains("Gloves are on."))
    }

    @Test("format splits into a new cue after sentence-ending punctuation")
    func formatSplitsOnSentenceEnd() {
        let segments = [
            TranscriptionSegment(text: "Gloves", timestamp: 0.0, duration: 0.4),
            TranscriptionSegment(text: "on.", timestamp: 0.4, duration: 0.3),
            TranscriptionSegment(text: "Sample", timestamp: 1.0, duration: 0.4),
            TranscriptionSegment(text: "ready.", timestamp: 1.4, duration: 0.3),
        ]
        let vtt = WebVTTFormatter.format(segments: segments)
        let cueCount = vtt.components(separatedBy: "-->").count - 1
        #expect(cueCount == 2)
        #expect(vtt.contains("Gloves on."))
        #expect(vtt.contains("Sample ready."))
    }

    @Test("format returns a bare WEBVTT header for empty segments")
    func formatEmptySegments() {
        #expect(WebVTTFormatter.format(segments: []) == "WEBVTT\n")
    }

    @Test("formatSingleCue wraps the whole text in one cue spanning the given duration")
    func formatSingleCueSpansDuration() {
        let vtt = WebVTTFormatter.formatSingleCue(text: "Gloves are on.", duration: 2.5)
        #expect(vtt.contains("00:00:00.000 --> 00:00:02.500"))
        #expect(vtt.contains("Gloves are on."))
    }

    @Test("extractPlainText strips the WEBVTT header and timestamp lines, joining cue text")
    func extractPlainTextStripsMarkup() {
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:00.900\nGloves are on.\n\n00:00:01.000 --> 00:00:01.700\nSample ready.\n\n"
        let plain = WebVTTFormatter.extractPlainText(from: vtt)
        #expect(plain == "Gloves are on. Sample ready.")
    }
}
