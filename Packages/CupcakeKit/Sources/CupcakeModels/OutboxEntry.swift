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
    /// Strict FIFO replay order — assigned by `OutboxStore.enqueue` as one-past-the-current-max,
    /// **not** derived from `createdAt`. Two entries created in rapid succession (e.g. a section
    /// added immediately after its just-created parent protocol) can land on the exact same
    /// `Date()` tick, which would make `sortBy: [SortDescriptor(\.createdAt)]` order them
    /// arbitrarily — and a section replayed before its protocol would spuriously hit
    /// `ProtocolSyncError.parentNotSynced` on its first attempt. `sequence` is guaranteed
    /// strictly increasing regardless of clock resolution.
    public var sequence: Int

    public init(
        id: UUID = UUID(),
        operationType: String,
        payloadJSON: Data,
        relatedClientID: UUID,
        status: String = OutboxEntryStatus.pending.rawValue,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        sequence: Int = 0
    ) {
        self.id = id
        self.operationType = operationType
        self.payloadJSON = payloadJSON
        self.relatedClientID = relatedClientID
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.sequence = sequence
    }
}

public enum OutboxEntryStatus: String, Sendable {
    case pending
    case failed
}

/// One case per outbox-eligible create operation.
public enum OutboxOperationType: String, Sendable {
    case createProtocol
    case createSection
    case createStep
    case createSession
    case createStepReagent
    case createTextAnnotation
    case createStoredReagent
    case createReagentAction
    case createInstrumentUsage
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

/// `OutboxEntry.payloadJSON` for operations that need no field snapshot at all —
/// `.createSection`/`.createStep`/`.createSession`. `relatedClientID` alone is enough to look the
/// local record back up at replay time and read its *current* fields (and, crucially, its
/// parent's now-possibly-synced `serverID`) directly, since those can change between enqueue and
/// replay in ways a frozen snapshot wouldn't reflect. Still a distinct, named type (rather than
/// no payload at all) so the pattern reads the same as every other operation's.
public struct EmptyOutboxPayload: Codable, Sendable {
    public init() {}
}
