import Foundation
import SwiftData

/// Read-only location tree for lookup — never offline-createable (§3).
@Model
public final class CachedStorageObject {
    @Attribute(.unique) public var serverID: Int64
    public var objectType: String
    public var objectName: String
    public var objectDescription: String?
    public var storedAtServerID: Int64?

    public init(
        serverID: Int64,
        objectType: String,
        objectName: String,
        objectDescription: String? = nil,
        storedAtServerID: Int64? = nil
    ) {
        self.serverID = serverID
        self.objectType = objectType
        self.objectName = objectName
        self.objectDescription = objectDescription
        self.storedAtServerID = storedAtServerID
    }
}
