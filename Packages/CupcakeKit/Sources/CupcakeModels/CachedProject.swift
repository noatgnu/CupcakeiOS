import Foundation
import SwiftData

@Model
public final class CachedProject {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var projectName: String
    public var projectDescription: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        projectName: String,
        projectDescription: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.projectName = projectName
        self.projectDescription = projectDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
