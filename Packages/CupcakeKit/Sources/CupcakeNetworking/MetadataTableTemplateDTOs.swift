public struct MetadataTableTemplateDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let ownerUsername: String?
    public let visibility: String
    public let isDefault: Bool
    public let columnCount: Int
    public let labGroup: Int64?
}

public struct CreateMetadataTableTemplateRequest: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var labGroup: Int64?
    public var visibility: String

    public init(name: String, description: String? = nil, labGroup: Int64? = nil, visibility: String = "private") {
        self.name = name
        self.description = description
        self.labGroup = labGroup
        self.visibility = visibility
    }
}

public struct CreateMetadataTableTemplateFromSchemaRequest: Encodable, Sendable {
    public var name: String
    public var schemas: [String]
    public var description: String?
    public var labGroup: Int64?

    public init(name: String, schemas: [String], description: String? = nil, labGroup: Int64? = nil) {
        self.name = name
        self.schemas = schemas
        self.description = description
        self.labGroup = labGroup
    }
}
