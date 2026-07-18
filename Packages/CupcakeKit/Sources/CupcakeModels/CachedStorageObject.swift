import Foundation
import SwiftData

@Model
public final class CachedStorageObject {
    @Attribute(.unique) public var serverID: Int64
    public var objectType: String
    public var objectName: String
    public var objectDescription: String?
    public var storedAtServerID: Int64?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        serverID: Int64,
        objectType: String,
        objectName: String,
        objectDescription: String? = nil,
        storedAtServerID: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.objectType = objectType
        self.objectName = objectName
        self.objectDescription = objectDescription
        self.storedAtServerID = storedAtServerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
