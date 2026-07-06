/// Field names verified directly against `ccrv/serializers.py`'s `StepAnnotationSerializer`.
public struct StepAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let session: Int64
    public let step: Int64
    public let annotation: Int64
    public let annotationText: String
    public let annotationType: String
    public let order: Int
}

/// The `annotation_data` shortcut `StepAnnotationViewSet.create()` reads (`ccrv/viewsets.py`) —
/// creates the underlying `Annotation` row server-side inline. Only for non-file annotation
/// types (text, molarity/calculator, booking); photo/audio/video/sketch go through chunked
/// upload instead (Phase 2).
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

/// `POST step-annotations/` body using the `annotation_data` shortcut. The outer `annotation`
/// FK is populated server-side from `annotation_data` — never sent directly by this path.
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
