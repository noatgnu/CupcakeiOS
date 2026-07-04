import Foundation
import SwiftData

/// `clientID` is the real identity (a session can be started fully offline from a cached or
/// locally-created protocol, per §4.2/§4.3 — it may never get a `serverID`). `uniqueID` mirrors
/// the server's own `unique_id` display field once synced; it is server-generated, never
/// client-assigned, so it can't double as the local identity the way it might first appear to.
/// `protocolServerIDs` is kept for network-fidelity/display of the server's M2M relationship;
/// `primaryProtocolClientID` is what the UI actually navigates with, since it works the same way
/// whether the session (and its protocol) originated online or fully locally.
@Model
public final class CachedSession {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var uniqueID: String?
    public var name: String?
    public var enabled: Bool
    /// Nullable because the server's own computation of this can serialize as JSON `null` for
    /// an unstarted session — see `SessionDTO`'s doc comment for the exact Python short-circuit
    /// bug that causes it.
    public var isRunning: Bool?
    public var status: String
    public var protocolServerIDs: [Int64]
    public var primaryProtocolClientID: UUID?
    /// When this device first learned about the session — its own creation time for a
    /// locally-created session, or first-sync time for one fetched from the server (an
    /// approximation there, since `SessionDTO` doesn't carry the server's own `created_at`).
    /// Used only for sorting the sessions list, matching the reference web app's
    /// `ordering: '-created_at'` (`session-list.ts:54-85`).
    public var createdAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        uniqueID: String? = nil,
        name: String?,
        enabled: Bool,
        isRunning: Bool?,
        status: String,
        protocolServerIDs: [Int64] = [],
        primaryProtocolClientID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.uniqueID = uniqueID
        self.name = name
        self.enabled = enabled
        self.isRunning = isRunning
        self.status = status
        self.protocolServerIDs = protocolServerIDs
        self.primaryProtocolClientID = primaryProtocolClientID
        self.createdAt = createdAt
    }
}
