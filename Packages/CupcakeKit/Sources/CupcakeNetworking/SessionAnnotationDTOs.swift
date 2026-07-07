public struct SessionAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let annotationText: String
    public let annotationType: String
    public let order: Int
    public let scratched: Bool
    public let fileUrl: String?
    public let transcription: String?
    public let language: String?
    public let translation: String?
    public let createdAt: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        session = try container.decode(Int64.self, forKey: .session)
        annotationText = try container.decode(String.self, forKey: .annotationText)
        annotationType = try container.decode(String.self, forKey: .annotationType)
        order = try container.decode(Int.self, forKey: .order)
        scratched = try container.decodeIfPresent(Bool.self, forKey: .scratched) ?? false
        fileUrl = try container.decodeIfPresent(String.self, forKey: .fileUrl)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, session, annotationText, annotationType, order, scratched, fileUrl
        case transcription, language, translation, createdAt
    }
}

public struct UpdateSessionAnnotationTranscriptionRequest: Encodable, Sendable {
    public var transcription: String?
    public var language: String?
    public var translation: String?

    public init(transcription: String?, language: String?, translation: String?) {
        self.transcription = transcription
        self.language = language
        self.translation = translation
    }
}

public struct UpdateAnnotationScratchedRequest: Encodable, Sendable {
    public var scratched: Bool

    public init(scratched: Bool) {
        self.scratched = scratched
    }
}
