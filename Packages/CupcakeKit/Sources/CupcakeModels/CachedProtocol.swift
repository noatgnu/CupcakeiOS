import Foundation
import SwiftData

/// A protocol, either read-only reference data or authored by this app. `isLocallyAuthored`, not `serverID == nil`, governs editability.
@Model
public final class CachedProtocol {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var protocolTitle: String
    public var protocolDescription: String?
    public var enabled: Bool
    public var isLocallyAuthored: Bool

    @Relationship(deleteRule: .cascade, inverse: \CachedProtocolSection.protocolModel)
    public var sections: [CachedProtocolSection] = []

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        protocolTitle: String,
        protocolDescription: String? = nil,
        enabled: Bool,
        isLocallyAuthored: Bool = false
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.protocolTitle = protocolTitle
        self.protocolDescription = protocolDescription
        self.enabled = enabled
        self.isLocallyAuthored = isLocallyAuthored
    }
}
