public struct FavouriteMetadataOptionDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let type: String
    public let value: String?
    public let displayValue: String?
    public let userUsername: String?
    public let labGroupName: String?
    public let isGlobal: Bool
}

public struct CreateFavouriteMetadataOptionRequest: Encodable, Sendable {
    public var name: String
    public var type: String
    public var value: String
    public var displayValue: String?
    public var user: Int64?
    public var labGroup: Int64?
    public var isGlobal: Bool

    public init(
        name: String,
        type: String,
        value: String,
        displayValue: String? = nil,
        user: Int64? = nil,
        labGroup: Int64? = nil,
        isGlobal: Bool = false
    ) {
        self.name = name
        self.type = type
        self.value = value
        self.displayValue = displayValue ?? value
        self.user = user
        self.labGroup = labGroup
        self.isGlobal = isGlobal
    }
}
