import Foundation
import SwiftData

@Model
public final class CachedProtocolRating {
    @Attribute(.unique) public var protocolServerID: Int64
    public var serverID: Int64
    public var complexityRating: Int
    public var durationRating: Int

    public init(protocolServerID: Int64, serverID: Int64, complexityRating: Int, durationRating: Int) {
        self.protocolServerID = protocolServerID
        self.serverID = serverID
        self.complexityRating = complexityRating
        self.durationRating = durationRating
    }
}
