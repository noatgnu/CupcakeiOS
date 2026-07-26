import Foundation

public struct WebVTTCue: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

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

    public static func parse(_ vtt: String) -> [WebVTTCue] {
        let lines = vtt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cues: [WebVTTCue] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line != "WEBVTT", !line.hasPrefix("WEBVTT "), !line.hasPrefix("NOTE") else {
                index += 1
                continue
            }
            guard line.contains("-->") else {
                index += 1
                continue
            }
            guard let (start, end) = parseTimestampLine(line) else {
                index += 1
                continue
            }
            index += 1
            var textLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[index])
                index += 1
            }
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                cues.append(WebVTTCue(start: start, end: end, text: text))
            }
        }
        return cues
    }

    public static func serialize(cues: [WebVTTCue]) -> String {
        build(cues: cues.map { (start: $0.start, end: $0.end, text: $0.text) })
    }

    private static func parseTimestampLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).first ?? ""
        guard let start = parseTimestamp(startText), let end = parseTimestamp(endText) else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ text: String) -> TimeInterval? {
        let components = text.components(separatedBy: ":")
        guard components.count == 2 || components.count == 3 else { return nil }
        guard let seconds = Double(components[components.count - 1]) else { return nil }
        guard let minutes = Double(components[components.count - 2]) else { return nil }
        var hours: Double = 0
        if components.count == 3 {
            guard let parsedHours = Double(components[0]) else { return nil }
            hours = parsedHours
        }
        return hours * 3600 + minutes * 60 + seconds
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
