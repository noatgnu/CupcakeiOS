import Foundation
import SwiftData

/// Read-only when fetched from the server's reagent catalog, but standalone/offline authoring
/// (creating a reagent locally to attach to a step you're writing from scratch, with no server
/// configured at all) needs its own identity too — same `clientID`-first,
/// `serverID`-once-synced pattern as the rest of the offline-createable models.
@Model
public final class CachedReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var name: String
    public var unit: String

    public init(clientID: UUID = UUID(), serverID: Int64? = nil, name: String, unit: String) {
        self.clientID = clientID
        self.serverID = serverID
        self.name = name
        self.unit = unit
    }
}
