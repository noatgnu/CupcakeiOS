public struct MetadataTableTemplateDTO: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let ownerUsername: String?
    public let visibility: String
    public let isDefault: Bool
    public let columnCount: Int
    public let labGroup: Int64?
    public let canEdit: Bool
    public let canDelete: Bool
    public let schemaNames: [String]

    public init(
        id: Int64,
        name: String,
        description: String?,
        ownerUsername: String?,
        visibility: String,
        isDefault: Bool,
        columnCount: Int,
        labGroup: Int64?,
        canEdit: Bool,
        canDelete: Bool,
        schemaNames: [String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.ownerUsername = ownerUsername
        self.visibility = visibility
        self.isDefault = isDefault
        self.columnCount = columnCount
        self.labGroup = labGroup
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.schemaNames = schemaNames
    }
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
