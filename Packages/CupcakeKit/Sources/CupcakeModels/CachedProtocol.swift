import Foundation
import SwiftData

@Model
public final class CachedProtocol {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var protocolTitle: String
    public var protocolDescription: String?
    public var enabled: Bool
    public var isLocallyAuthored: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var ownerServerID: Int64?
    public var editorServerIDs: [Int64]
    public var viewerServerIDs: [Int64]

    @Relationship(deleteRule: .cascade, inverse: \CachedProtocolSection.protocolModel)
    public var sections: [CachedProtocolSection] = []

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        protocolTitle: String,
        protocolDescription: String? = nil,
        enabled: Bool,
        isLocallyAuthored: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        ownerServerID: Int64? = nil,
        editorServerIDs: [Int64] = [],
        viewerServerIDs: [Int64] = []
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.protocolTitle = protocolTitle
        self.protocolDescription = protocolDescription
        self.enabled = enabled
        self.isLocallyAuthored = isLocallyAuthored
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerServerID = ownerServerID
        self.editorServerIDs = editorServerIDs
        self.viewerServerIDs = viewerServerIDs
    }
}
