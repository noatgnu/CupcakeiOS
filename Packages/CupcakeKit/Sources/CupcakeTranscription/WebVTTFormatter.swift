import Foundation

public enum WebVTTFormatter {
    private static let sentenceEndings: Set<Character> = [".", "?", "!"]
    private static let maxCueDuration: TimeInterval = 6

    public static func format(segments: [TranscriptionSegment]) -> String {
        guard !segments.isEmpty else { return "WEBVTT\n" }

        var cues: [(start: TimeInterval, end: TimeInterval, text: String)] = []
        var cueWords: [TranscriptionSegment] = []

        func flush() {
            guard let first = cueWords.first, let last = cueWords.last else { return }
            let text = cueWords.map(\.text).joined(separator: " ")
            cues.append((start: first.timestamp, end: last.timestamp + last.duration, text: text))
            cueWords.removeAll()
        }

        for segment in segments {
            cueWords.append(segment)
            let cueStart = cueWords.first?.timestamp ?? segment.timestamp
            let cueEnd = segment.timestamp + segment.duration
            let endsSentence = segment.text.last.map { sentenceEndings.contains($0) } ?? false
            if endsSentence || (cueEnd - cueStart) >= maxCueDuration {
                flush()
            }
        }
        flush()

        return build(cues: cues)
    }

    public static func formatSingleCue(text: String, duration: TimeInterval) -> String {
        build(cues: [(start: 0, end: duration, text: text)])
    }

    public static func extractPlainText(from vtt: String) -> String {
        vtt.split(separator: "\n")
            .filter { !$0.isEmpty && $0 != "WEBVTT" && !$0.contains("-->") }
            .joined(separator: " ")
    }

    private static func build(cues: [(start: TimeInterval, end: TimeInterval, text: String)]) -> String {
        var vtt = "WEBVTT\n\n"
        for cue in cues {
            vtt += "\(timestamp(cue.start)) --> \(timestamp(cue.end))\n"
            vtt += "\(cue.text)\n\n"
        }
        return vtt
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = seconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%02d:%02d:%06.3f", hours, minutes, secs)
    }
}
