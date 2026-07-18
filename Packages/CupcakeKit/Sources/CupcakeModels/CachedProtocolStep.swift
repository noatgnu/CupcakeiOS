import Foundation
import SwiftData

@Model
public final class CachedProtocolStep {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var stepDescription: String
    public var order: Int
    public var stepDuration: Int?
    public var section: CachedProtocolSection?

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        stepDescription: String,
        order: Int,
        stepDuration: Int? = nil,
        section: CachedProtocolSection? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.stepDescription = stepDescription
        self.order = order
        self.stepDuration = stepDuration
        self.section = section
    }
}
