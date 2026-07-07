import Foundation
import SwiftData

@Model
public final class CachedMetadataTableTemplate {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var templateDescription: String?
    public var ownerUsername: String?
    public var visibility: String
    public var isDefault: Bool
    public var columnCount: Int
    public var labGroupServerID: Int64?
    public var canEdit: Bool
    public var canDelete: Bool
    public var schemaNames: [String]

    public init(
        serverID: Int64,
        name: String,
        templateDescription: String? = nil,
        ownerUsername: String? = nil,
        visibility: String = "private",
        isDefault: Bool = false,
        columnCount: Int = 0,
        labGroupServerID: Int64? = nil,
        canEdit: Bool = false,
        canDelete: Bool = false,
        schemaNames: [String] = []
    ) {
        self.serverID = serverID
        self.name = name
        self.templateDescription = templateDescription
        self.ownerUsername = ownerUsername
        self.visibility = visibility
        self.isDefault = isDefault
        self.columnCount = columnCount
        self.labGroupServerID = labGroupServerID
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.schemaNames = schemaNames
    }
}
