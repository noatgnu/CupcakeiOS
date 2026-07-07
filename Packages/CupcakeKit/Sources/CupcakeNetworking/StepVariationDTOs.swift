public struct StepVariationDTO: Decodable, Sendable {
    public let id: Int64
    public let step: Int64
    public let session: Int64?
    public let variationDescription: String
    public let variationDuration: Int
}

public struct CreateStepVariationRequest: Encodable, Sendable {
    public var step: Int64
    public var session: Int64?
    public var variationDescription: String
    public var variationDuration: Int

    public init(step: Int64, session: Int64? = nil, variationDescription: String, variationDuration: Int) {
        self.step = step
        self.session = session
        self.variationDescription = variationDescription
        self.variationDuration = variationDuration
    }
}
