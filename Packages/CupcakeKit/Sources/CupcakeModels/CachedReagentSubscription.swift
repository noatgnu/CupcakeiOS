import Foundation
import SwiftData

@Model
public final class CachedReagentSubscription {
    @Attribute(.unique) public var storedReagentServerID: Int64
    public var serverID: Int64
    public var notifyOnLowStock: Bool
    public var notifyOnExpiry: Bool

    public init(storedReagentServerID: Int64, serverID: Int64, notifyOnLowStock: Bool, notifyOnExpiry: Bool) {
        self.storedReagentServerID = storedReagentServerID
        self.serverID = serverID
        self.notifyOnLowStock = notifyOnLowStock
        self.notifyOnExpiry = notifyOnExpiry
    }
}
