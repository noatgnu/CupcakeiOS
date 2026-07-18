import Foundation
import SwiftData

@Model
public final class CachedProtocolSection {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var sectionDescription: String?
    public var order: Int
    public var sectionDuration: Int?
    public var protocolModel: CachedProtocol?

    @Relationship(deleteRule: .cascade, inverse: \CachedProtocolStep.section)
    public var steps: [CachedProtocolStep] = []

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        sectionDescription: String? = nil,
        order: Int,
        sectionDuration: Int? = nil,
        protocolModel: CachedProtocol? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.sectionDescription = sectionDescription
        self.order = order
        self.sectionDuration = sectionDuration
        self.protocolModel = protocolModel
    }
}
