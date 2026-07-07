import Foundation
import SwiftData

/// Offline-createable project. The one link between the Session/Protocol world and `InstrumentJob`.
@Model
public final class CachedProject {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var projectName: String
    public var projectDescription: String?

    public init(clientID: UUID = UUID(), serverID: Int64? = nil, projectName: String, projectDescription: String? = nil) {
        self.clientID = clientID
        self.serverID = serverID
        self.projectName = projectName
        self.projectDescription = projectDescription
    }
}
