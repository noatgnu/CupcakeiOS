import Foundation
import SwiftData

@Model
public final class CachedReagentAction {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var storedReagentClientID: UUID
    public var actionType: String
    public var quantity: Double
    public var notes: String?
    public var createdAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        storedReagentClientID: UUID,
        actionType: String,
        quantity: Double,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.storedReagentClientID = storedReagentClientID
        self.actionType = actionType
        self.quantity = quantity
        self.notes = notes
        self.createdAt = createdAt
    }
}
