import Foundation
import SwiftData

/// Offline-createable, same client-generated-identity pattern as everything else authored by
/// this app. Part of the `InstrumentJob` subsystem (Phase 4.5) — independent of Session/Protocol,
/// the only cross-app link is `projectClientID`/`projectServerID`. Only the fields this app's v1
/// Job-slice needs are modeled (see `InstrumentJobDTO`'s doc comment for what's deferred).
@Model
public final class CachedInstrumentJob {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var jobName: String?
    public var jobType: String
    public var status: String
    /// The parent project's `clientID` — not its `serverID`, since a locally-created project
    /// may not have one yet (same reasoning as every other not-yet-synced-parent reference in
    /// this app, e.g. `CachedStepReagent.reagentClientID`). `nil` if the job has no project.
    public var projectClientID: UUID?
    public var instrumentServerID: Int64?
    public var submittedAt: String?
    public var completedAt: String?

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        jobName: String? = nil,
        jobType: String = "analysis",
        status: String = "draft",
        projectClientID: UUID? = nil,
        instrumentServerID: Int64? = nil,
        submittedAt: String? = nil,
        completedAt: String? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.jobName = jobName
        self.jobType = jobType
        self.status = status
        self.projectClientID = projectClientID
        self.instrumentServerID = instrumentServerID
        self.submittedAt = submittedAt
        self.completedAt = completedAt
    }
}
