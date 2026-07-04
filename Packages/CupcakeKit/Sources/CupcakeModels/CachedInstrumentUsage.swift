import Foundation
import SwiftData

/// A booking request — offline-createable from Phase 3 on, so this uses the same
/// client-generated-identity pattern as `CachedStoredReagent`. Approval always happens
/// server-side later regardless of where the booking was created.
@Model
public final class CachedInstrumentUsage {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var instrumentServerID: Int64
    public var instrumentName: String
    public var timeStarted: String?
    public var timeEnded: String?
    public var usageDescription: String
    public var approved: Bool
    public var maintenance: Bool

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        instrumentServerID: Int64,
        instrumentName: String,
        timeStarted: String? = nil,
        timeEnded: String? = nil,
        usageDescription: String,
        approved: Bool,
        maintenance: Bool
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.instrumentServerID = instrumentServerID
        self.instrumentName = instrumentName
        self.timeStarted = timeStarted
        self.timeEnded = timeEnded
        self.usageDescription = usageDescription
        self.approved = approved
        self.maintenance = maintenance
    }
}
