import Foundation

public struct TranscriptionVocabularyTerm: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public enum TranscriptionVocabularyStore {
    private static let defaultsKey = "cupcake.transcriptionVocabularyTerms"

    public static func allTerms(defaults: UserDefaults = .standard) -> [TranscriptionVocabularyTerm] {
        guard let data = defaults.data(forKey: defaultsKey),
              let terms = try? JSONDecoder().decode([TranscriptionVocabularyTerm].self, from: data) else {
            return []
        }
        return terms
    }

    public static func currentTexts(defaults: UserDefaults = .standard) -> [String] {
        allTerms(defaults: defaults).map(\.text)
    }

    public static func add(_ text: String, defaults: UserDefaults = .standard) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var terms = allTerms(defaults: defaults)
        terms.append(TranscriptionVocabularyTerm(text: trimmed))
        save(terms, defaults: defaults)
    }

    public static func remove(id: UUID, defaults: UserDefaults = .standard) {
        var terms = allTerms(defaults: defaults)
        terms.removeAll { $0.id == id }
        save(terms, defaults: defaults)
    }

    private static func save(_ terms: [TranscriptionVocabularyTerm], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
