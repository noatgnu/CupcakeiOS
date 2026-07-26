import Foundation

public enum WhisperKitMapping {
    public static func whisperLanguageCode(from localeIdentifier: String) -> String {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? "en"
    }

    public static func makeSegment(text: String, start: Float, end: Float) -> TranscriptionSegment {
        TranscriptionSegment(text: stripSpecialTokens(from: text), timestamp: TimeInterval(start), duration: TimeInterval(end - start))
    }

    public static func glossaryPrompt(vocabulary: [String]) -> String? {
        guard !vocabulary.isEmpty else { return nil }
        return "Glossary: " + vocabulary.joined(separator: ", ")
    }

    private static let specialTokenPattern = try! NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: [])

    public static func stripSpecialTokens(from text: String) -> String {
        guard text.contains("<|") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = specialTokenPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
