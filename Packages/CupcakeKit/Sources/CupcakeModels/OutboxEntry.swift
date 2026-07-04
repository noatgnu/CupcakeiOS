import Foundation
import SwiftData

/// A queued create operation that couldn't reach the server yet — the record it's for was
/// already created locally (so nothing is lost or blocked on the network), and this entry is
/// what lets `OutboxService.replayPending()` retry the actual server write later, on
/// reconnect (`NWPathMonitor`) or a manual "Retry Sync" action.
///
/// Only created for a signed-in device whose write failed due to genuine unreachability
/// (`APIError.transport`) — a server-rejected request (`APIError.http`, a real validation/auth
/// error) is surfaced to the user immediately instead, since retrying it would never succeed.
/// A pure standalone-mode creation (never signed in) never gets an outbox entry at all — that's
/// permanently local until the Phase 6 import flow exists.
@Model
public final class OutboxEntry {
    @Attribute(.unique) public var id: UUID
    /// Matches an `OutboxOperationType` raw value — kept as a plain `String` (not the enum
    /// itself) since `@Model` properties need to be simple, migratable value types.
    public var operationType: String
    /// JSON-encoded operation-specific payload (e.g. `CreateProtocolPayload`) — decoded by
    /// `OutboxService.replay(_:)` based on `operationType`.
    public var payloadJSON: Data
    /// The `clientID` of the local record this operation is meant to sync — lets the replay
    /// path find and update the existing local record (attach its new `serverID`) rather than
    /// creating a duplicate.
    public var relatedClientID: UUID
    public var status: String
    public var retryCount: Int
    public var lastError: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        operationType: String,
        payloadJSON: Data,
        relatedClientID: UUID,
        status: String = OutboxEntryStatus.pending.rawValue,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.operationType = operationType
        self.payloadJSON = payloadJSON
        self.relatedClientID = relatedClientID
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
    }
}

public enum OutboxEntryStatus: String, Sendable {
    case pending
    case failed
}

/// One case per outbox-eligible create operation. Only `createProtocol` is wired up to actually
/// replay yet (see `OutboxService`'s doc comment) — the others are listed here so the pattern is
/// visible for whoever extends it next, not because they're implemented.
public enum OutboxOperationType: String, Sendable {
    case createProtocol
}

/// `OutboxEntry.payloadJSON` for `OutboxOperationType.createProtocol` — a plain `Codable` twin of
/// `CupcakeNetworking.CreateProtocolRequest` (which is `Encodable`-only, since it's meant for a
/// live HTTP body, not round-tripping through storage). Lives here, not in `CupcakeNetworking`,
/// because `CupcakeModels` has zero dependencies and the outbox is fundamentally storage, not a
/// network concern.
public struct CreateProtocolPayload: Codable, Sendable {
    public var title: String
    public var description: String?
    public var enabled: Bool

    public init(title: String, description: String?, enabled: Bool) {
        self.title = title
        self.description = description
        self.enabled = enabled
    }
}
