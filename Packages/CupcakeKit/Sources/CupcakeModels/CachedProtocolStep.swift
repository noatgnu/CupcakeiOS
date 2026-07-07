import Foundation
import SwiftData

/// A protocol step. `clientID` is the real persistent identity; `serverID` may never be set in standalone mode.
@Model
public final class CachedProtocolStep {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var stepDescription: String
    public var order: Int
    /// Seconds, not minutes.
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
