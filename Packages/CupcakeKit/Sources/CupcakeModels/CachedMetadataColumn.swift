import Foundation
import SwiftData

/// Read-only in this app's v1 slice — `update_column_value` editing is deferred.
@Model
public final class CachedMetadataColumn {
    @Attribute(.unique) public var serverID: Int64
    public var metadataTableServerID: Int64
    public var name: String
    public var displayName: String?
    public var type: String
    public var columnPosition: Int
    public var value: String?
    public var notApplicable: Bool
    public var notAvailable: Bool
    public var mandatory: Bool
    public var hidden: Bool
    public var readonly: Bool
    public var ontologyType: String?
    public var staffOnly: Bool

    public init(
        serverID: Int64,
        metadataTableServerID: Int64,
        name: String,
        displayName: String? = nil,
        type: String,
        columnPosition: Int = 0,
        value: String? = nil,
        notApplicable: Bool = false,
        notAvailable: Bool = false,
        mandatory: Bool = false,
        hidden: Bool = false,
        readonly: Bool = false,
        ontologyType: String? = nil,
        staffOnly: Bool = false
    ) {
        self.serverID = serverID
        self.metadataTableServerID = metadataTableServerID
        self.name = name
        self.displayName = displayName
        self.type = type
        self.columnPosition = columnPosition
        self.value = value
        self.notApplicable = notApplicable
        self.notAvailable = notAvailable
        self.mandatory = mandatory
        self.hidden = hidden
        self.readonly = readonly
        self.ontologyType = ontologyType
        self.staffOnly = staffOnly
    }
}
