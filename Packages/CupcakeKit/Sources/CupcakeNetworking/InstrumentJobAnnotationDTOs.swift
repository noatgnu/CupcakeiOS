/// Verified against `ccm/serializers.py:987-1137` (`InstrumentJobAnnotationSerializer`) and
/// `ccm/viewsets.py:1682-1852` (`InstrumentJobAnnotationViewSet`).
public struct InstrumentJobAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentJob: Int64
    public let annotationText: String?
    public let annotationType: String?
    public let role: String
    public let order: Int
}

/// `POST instrument-job-annotations/` body, using the same `annotation_data` shortcut already
/// established for `StepAnnotation` (`AnnotationDataRequest`, `StepAnnotationDTOs.swift`). The
/// reference web app always sends `role: "staff"` for booking annotations regardless of who's
/// booking, matched here rather than assumed.
public struct CreateInstrumentJobAnnotationRequest: Encodable, Sendable {
    public var instrumentJob: Int64
    public var annotationData: AnnotationDataRequest
    public var role: String

    public init(instrumentJob: Int64, annotationData: AnnotationDataRequest, role: String = "staff") {
        self.instrumentJob = instrumentJob
        self.annotationData = annotationData
        self.role = role
    }
}

/// Verified against `ccm/serializers.py:1140-1169` / `ccm/viewsets.py:1854-1921`
/// (`InstrumentUsageJobAnnotationSerializer`/`ViewSet`) — purely a display/lookup link, not
/// consulted by the metadata-merge signal itself (which only checks the annotation's
/// `annotation_type`).
public struct InstrumentUsageJobAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentJobAnnotation: Int64
    public let instrumentUsage: Int64
}

public struct CreateInstrumentUsageJobAnnotationRequest: Encodable, Sendable {
    public var instrumentJobAnnotation: Int64
    public var instrumentUsage: Int64

    public init(instrumentJobAnnotation: Int64, instrumentUsage: Int64) {
        self.instrumentJobAnnotation = instrumentJobAnnotation
        self.instrumentUsage = instrumentUsage
    }
}
