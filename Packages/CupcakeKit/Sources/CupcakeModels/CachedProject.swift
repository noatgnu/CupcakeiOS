import Foundation
import SwiftData

/// Offline-createable, same client-generated-identity pattern as everything else authored by
/// this app. `Project` (`ccrv.Project`) is the one cross-app link between the CCRV
/// (Session/Protocol) world and the CCM `InstrumentJob` subsystem — a job's `project` FK is the
/// only relationship connecting the two, confirmed by grepping both directions (no FK exists
/// from `InstrumentJob` to `Session`/`Protocol`/`Step` at all).
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
