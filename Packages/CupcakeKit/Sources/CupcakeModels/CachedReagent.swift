import Foundation
import SwiftData

/// A reagent, either fetched from the server catalog or created locally.
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
