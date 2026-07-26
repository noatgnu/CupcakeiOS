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

    @Test("parse then serialize round-trips a real format(segments:) output exactly")
    func parseSerializeRoundTripsFormatOutput() {
        let segments = [
            TranscriptionSegment(text: "Gloves", timestamp: 0.0, duration: 0.4),
            TranscriptionSegment(text: "on.", timestamp: 0.4, duration: 0.3),
            TranscriptionSegment(text: "Sample", timestamp: 1.0, duration: 0.4),
            TranscriptionSegment(text: "ready.", timestamp: 1.4, duration: 0.3),
        ]
        let original = WebVTTFormatter.format(segments: segments)
        let cues = WebVTTFormatter.parse(original)
        #expect(cues.count == 2)
        #expect(cues[0].text == "Gloves on.")
        #expect(cues[0].start == 0.0)
        #expect(cues[0].end == 0.7)
        #expect(cues[1].text == "Sample ready.")
        let roundTripped = WebVTTFormatter.serialize(cues: cues)
        #expect(roundTripped == original)
    }

    @Test("parse tolerates real-world formatting variance: extra whitespace, no trailing blank line, cue identifiers, cue settings")
    func parseTolerantOfVariance() {
        let vtt = """
        WEBVTT

        1
        00:00:00.000 --> 00:00:00.900 align:middle line:90%
          Gloves are on.

        2
        00:00:01.000   -->   00:00:01.700
        Sample ready.
        """
        let cues = WebVTTFormatter.parse(vtt)
        #expect(cues.count == 2)
        #expect(cues[0].start == 0.0)
        #expect(cues[0].end == 0.9)
        #expect(cues[0].text == "Gloves are on.")
        #expect(cues[1].start == 1.0)
        #expect(cues[1].end == 1.7)
        #expect(cues[1].text == "Sample ready.")
    }

    @Test("parse supports MM:SS.mmm timestamps without an hours component")
    func parseSupportsShortTimestamps() {
        let vtt = "WEBVTT\n\n00:05.500 --> 00:07.250\nHello.\n"
        let cues = WebVTTFormatter.parse(vtt)
        #expect(cues.count == 1)
        #expect(cues[0].start == 5.5)
        #expect(cues[0].end == 7.25)
    }

    @Test("parse returns an empty array for a bare WEBVTT header")
    func parseEmptyHeader() {
        #expect(WebVTTFormatter.parse("WEBVTT\n").isEmpty)
    }

    @Test("serialize produces cues that reformat the given start/end/text")
    func serializeProducesExpectedFormat() {
        let cues = [
            WebVTTCue(start: 0, end: 2.5, text: "Gloves are on."),
            WebVTTCue(start: 3, end: 4.125, text: "Sample ready."),
        ]
        let vtt = WebVTTFormatter.serialize(cues: cues)
        #expect(vtt.contains("00:00:00.000 --> 00:00:02.500"))
        #expect(vtt.contains("Gloves are on."))
        #expect(vtt.contains("00:00:03.000 --> 00:00:04.125"))
        #expect(vtt.contains("Sample ready."))
    }
}
