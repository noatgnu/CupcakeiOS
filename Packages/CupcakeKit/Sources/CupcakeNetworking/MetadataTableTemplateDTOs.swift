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
    public let userColumns: [MetadataColumnDTO]?
    public let createdAt: String?
    public let updatedAt: String?

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
        schemaNames: [String],
        userColumns: [MetadataColumnDTO]? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
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
        self.userColumns = userColumns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

public struct DuplicateMetadataTableTemplateRequest: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var userColumnIds: [Int64]
    public var visibility: String
    public var labGroup: Int64?

    public init(name: String, description: String?, userColumnIds: [Int64], visibility: String = "private", labGroup: Int64? = nil) {
        self.name = name
        self.description = description
        self.userColumnIds = userColumnIds
        self.visibility = visibility
        self.labGroup = labGroup
    }
}

public struct AddTemplateColumnRequest: Encodable, Sendable {
    public var columnData: AddColumnDataRequest
    public var position: Int?
    public var autoReorder: Bool?

    public init(columnData: AddColumnDataRequest, position: Int? = nil, autoReorder: Bool? = nil) {
        self.columnData = columnData
        self.position = position
        self.autoReorder = autoReorder
    }
}

public struct AddTemplateColumnResponse: Decodable, Sendable {
    public let message: String
    public let column: MetadataColumnDTO
    public let reordered: Bool?
    public let schemaIdsUsed: [Int64]?
}

public struct RemoveTemplateColumnRequest: Encodable, Sendable {
    public var columnId: Int64
    public init(columnId: Int64) { self.columnId = columnId }
}

public struct ReorderTemplateColumnRequest: Encodable, Sendable {
    public var columnId: Int64
    public var newPosition: Int
    public init(columnId: Int64, newPosition: Int) {
        self.columnId = columnId
        self.newPosition = newPosition
    }
}

public struct DuplicateTemplateColumnRequest: Encodable, Sendable {
    public var columnId: Int64
    public var newName: String?
    public init(columnId: Int64, newName: String? = nil) {
        self.columnId = columnId
        self.newName = newName
    }
}

public struct DuplicateTemplateColumnResponse: Decodable, Sendable {
    public let message: String
    public let column: MetadataColumnDTO
}

public struct SyncTemplateFromSchemasRequest: Encodable, Sendable {
    public var addNew: Bool
    public var updateExisting: Bool
    public var removeOrphans: Bool

    public init(addNew: Bool = true, updateExisting: Bool = true, removeOrphans: Bool = false) {
        self.addNew = addNew
        self.updateExisting = updateExisting
        self.removeOrphans = removeOrphans
    }
}

public struct SyncTemplateFromSchemasResponse: Decodable, Sendable {
    public let message: String
    public let added: Int
    public let updated: Int
    public let removed: Int
    public let errors: [String]
    public let schemas: [String]
}

public struct BulkDeleteTemplateColumnsRequest: Encodable, Sendable {
    public var columnIds: [Int64]
    public init(columnIds: [Int64]) { self.columnIds = columnIds }
}

public struct BulkDeleteTemplateColumnsResponse: Decodable, Sendable {
    public let message: String
    public let deletedCount: Int
}

public struct BulkUpdateStaffOnlyRequest: Encodable, Sendable {
    public var columnIds: [Int64]
    public var staffOnly: Bool
    public init(columnIds: [Int64], staffOnly: Bool) {
        self.columnIds = columnIds
        self.staffOnly = staffOnly
    }
}

public struct BulkUpdateStaffOnlyResponse: Decodable, Sendable {
    public let message: String
    public let updatedCount: Int
}
