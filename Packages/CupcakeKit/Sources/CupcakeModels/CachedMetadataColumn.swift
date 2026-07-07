import Foundation
import SwiftData

/// A per-sample-range value override, e.g. samples `"1-3,7"` use `value` instead of the column's default.
public struct MetadataColumnModifier: Codable, Sendable, Hashable {
    public var samples: String
    public var value: String

    public init(samples: String, value: String) {
        self.samples = samples
        self.value = value
    }
}

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
    public var modifiers: [MetadataColumnModifier]

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
        staffOnly: Bool = false,
        modifiers: [MetadataColumnModifier] = []
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
        self.modifiers = modifiers
    }
}
