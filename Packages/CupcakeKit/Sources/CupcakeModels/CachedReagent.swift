import Foundation
import SwiftData

@Model
public final class CachedReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var name: String
    public var unit: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        name: String,
        unit: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.name = name
        self.unit = unit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
