public struct InstrumentJobAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let instrumentJob: Int64
    public let annotationText: String?
    public let annotationType: String?
    public let role: String
    public let order: Int
}

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

public struct InstrumentUsageStepAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let stepAnnotation: Int64
    public let instrumentUsage: Int64
}

public struct CreateInstrumentUsageStepAnnotationRequest: Encodable, Sendable {
    public var stepAnnotation: Int64
    public var instrumentUsage: Int64

    public init(stepAnnotation: Int64, instrumentUsage: Int64) {
        self.stepAnnotation = stepAnnotation
        self.instrumentUsage = instrumentUsage
    }
}
