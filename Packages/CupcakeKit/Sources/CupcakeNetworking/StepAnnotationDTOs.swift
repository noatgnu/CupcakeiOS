public struct StepAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let step: Int64
    public let annotation: Int64
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
        step = try container.decode(Int64.self, forKey: .step)
        annotation = try container.decode(Int64.self, forKey: .annotation)
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
        case id, session, step, annotation, annotationText, annotationType, order, scratched, fileUrl
        case transcription, language, translation, createdAt
    }
}

public struct AnnotationDataRequest: Encodable, Sendable {
    public var annotationType: String
    public var annotation: String
    public var autoTranscribe: Bool

    public init(annotationType: String = "text", annotation: String, autoTranscribe: Bool = false) {
        self.annotationType = annotationType
        self.annotation = annotation
        self.autoTranscribe = autoTranscribe
    }
}

public struct CreateStepAnnotationRequest: Encodable, Sendable {
    public var session: Int64
    public var step: Int64
    public var annotationData: AnnotationDataRequest

    public init(session: Int64, step: Int64, annotationData: AnnotationDataRequest) {
        self.session = session
        self.step = step
        self.annotationData = annotationData
    }
}

public struct AnnotationChunkedUploadResponse: Decodable, Sendable {
    public let annotationId: Int64?
    public let stepAnnotationId: Int64?
    public let sessionAnnotationId: Int64?
    public let message: String?
    public let warning: String?
}

public struct UpdateStepAnnotationTranscriptionRequest: Encodable, Sendable {
    public var transcription: String?
    public var language: String?
    public var translation: String?

    public init(transcription: String?, language: String?, translation: String?) {
        self.transcription = transcription
        self.language = language
        self.translation = translation
    }
}
