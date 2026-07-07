import Foundation
import SwiftData

/// Read-only; always created server-side via `create_metadata_from_template`.
@Model
public final class CachedMetadataTable {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var tableDescription: String?
    public var sampleCount: Int
    public var version: String
    public var ownerUsername: String?
    public var labGroupName: String?
    public var isPublished: Bool
    public var canEdit: Bool
    /// The `CachedInstrumentJob.clientID` this table belongs to, resolved at upsert time.
    public var instrumentJobClientID: UUID?

    public init(
        serverID: Int64,
        name: String,
        tableDescription: String? = nil,
        sampleCount: Int = 0,
        version: String = "1.0",
        ownerUsername: String? = nil,
        labGroupName: String? = nil,
        isPublished: Bool = false,
        canEdit: Bool = false,
        instrumentJobClientID: UUID? = nil
    ) {
        self.serverID = serverID
        self.name = name
        self.tableDescription = tableDescription
        self.sampleCount = sampleCount
        self.version = version
        self.ownerUsername = ownerUsername
        self.labGroupName = labGroupName
        self.isPublished = isPublished
        self.canEdit = canEdit
        self.instrumentJobClientID = instrumentJobClientID
    }
}
