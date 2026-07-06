import Foundation
import SwiftData

/// Read-only server data — no offline-create path (mirrors `CachedInstrument`/`CachedStorageObject`).
@Model
public final class CachedLabGroup {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var groupDescription: String?
    public var allowProcessJobs: Bool

    public init(serverID: Int64, name: String, groupDescription: String? = nil, allowProcessJobs: Bool = false) {
        self.serverID = serverID
        self.name = name
        self.groupDescription = groupDescription
        self.allowProcessJobs = allowProcessJobs
    }
}
