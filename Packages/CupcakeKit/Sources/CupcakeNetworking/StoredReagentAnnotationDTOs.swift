public struct StoredReagentAnnotationDTO: Decodable, Sendable {
    public let id: Int64
    public let storedReagent: Int64
    public let folder: Int64
    public let folderName: String?
    public let annotationText: String
    public let annotationType: String
    public let scratched: Bool
}

public struct CreateStoredReagentAnnotationRequest: Encodable, Sendable {
    public var storedReagent: Int64
    public var folder: Int64
    public var annotationData: AnnotationDataRequest

    public init(storedReagent: Int64, folder: Int64, annotationType: String, annotation: String) {
        self.storedReagent = storedReagent
        self.folder = folder
        self.annotationData = AnnotationDataRequest(annotationType: annotationType, annotation: annotation)
    }
}
