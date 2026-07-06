import Foundation
import SwiftData

/// Read-only browsing — no template-authoring path in this app's v1 slice.
@Model
public final class CachedMetadataTableTemplate {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var templateDescription: String?
    public var ownerUsername: String?
    public var visibility: String
    public var isDefault: Bool
    public var columnCount: Int

    public init(
        serverID: Int64,
        name: String,
        templateDescription: String? = nil,
        ownerUsername: String? = nil,
        visibility: String = "private",
        isDefault: Bool = false,
        columnCount: Int = 0
    ) {
        self.serverID = serverID
        self.name = name
        self.templateDescription = templateDescription
        self.ownerUsername = ownerUsername
        self.visibility = visibility
        self.isDefault = isDefault
        self.columnCount = columnCount
    }
}
