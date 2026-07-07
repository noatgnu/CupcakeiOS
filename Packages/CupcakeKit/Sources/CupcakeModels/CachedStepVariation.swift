import Foundation
import SwiftData

/// A session-scoped alternate description/duration for a step. Server-ID-keyed, online-only.
@Model
public final class CachedStepVariation {
    @Attribute(.unique) public var serverID: Int64
    public var stepServerID: Int64
    public var sessionServerID: Int64?
    public var variationDescription: String
    public var variationDuration: Int

    public init(
        serverID: Int64,
        stepServerID: Int64,
        sessionServerID: Int64? = nil,
        variationDescription: String,
        variationDuration: Int
    ) {
        self.serverID = serverID
        self.stepServerID = stepServerID
        self.sessionServerID = sessionServerID
        self.variationDescription = variationDescription
        self.variationDuration = variationDuration
    }
}
