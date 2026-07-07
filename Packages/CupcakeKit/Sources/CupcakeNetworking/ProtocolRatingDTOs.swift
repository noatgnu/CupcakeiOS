public struct ProtocolRatingDTO: Decodable, Sendable {
    public let id: Int64
    public let protocol_: Int64
    public let complexityRating: Int
    public let durationRating: Int

    private enum CodingKeys: String, CodingKey {
        case id, protocol_ = "protocol", complexityRating, durationRating
    }
}

public struct RateProtocolRequest: Encodable, Sendable {
    public var protocol_: Int64
    public var complexityRating: Int
    public var durationRating: Int

    private enum CodingKeys: String, CodingKey {
        case protocol_ = "protocol", complexityRating, durationRating
    }

    public init(protocolServerID: Int64, complexityRating: Int, durationRating: Int) {
        self.protocol_ = protocolServerID
        self.complexityRating = complexityRating
        self.durationRating = durationRating
    }
}
