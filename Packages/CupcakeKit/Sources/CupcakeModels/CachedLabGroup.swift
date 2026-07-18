import Foundation
import SwiftData

@Model
public final class CachedLabGroup {
    @Attribute(.unique) public var serverID: Int64
    public var name: String
    public var groupDescription: String?
    public var allowProcessJobs: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        serverID: Int64,
        name: String,
        groupDescription: String? = nil,
        allowProcessJobs: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.name = name
        self.groupDescription = groupDescription
        self.allowProcessJobs = allowProcessJobs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
