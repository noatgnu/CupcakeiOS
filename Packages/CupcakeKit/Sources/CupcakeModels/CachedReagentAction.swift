import Foundation
import SwiftData

/// A stock movement against a `StoredReagent` — "add" or "reserve" are the only two real
/// `action_type` choices server-side (`ccm/models.py:700-703`; there is no "consume"). Offline-
/// createable, same client-generated-identity pattern as `CachedStoredReagent`.
///
/// `ReagentAction` has no `updated_at__gte` delta-sync filter and no deletion-log/tombstone
/// coverage on the server (confirmed directly against `ReagentActionViewSet` — unlike
/// `Instrument`/`InstrumentUsage`/`StoredReagent`, which all mix in `DeletionLogMixin`), so
/// `InventorySyncService.refetchReagentActions()` does a plain full-refetch every cycle rather
/// than a cursor-based one — the same reasoning `ProtocolSyncService.refetchAll()` used before
/// Phase 2 existed, just permanent here since there's no delta mechanism to graduate to.
@Model
public final class CachedReagentAction {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    /// The parent `StoredReagent`'s `clientID` — not its `serverID`, since a locally-created
    /// `StoredReagent` may not have one yet (same reasoning as `CachedStepReagent.stepClientID`).
    public var storedReagentClientID: UUID
    public var actionType: String
    public var quantity: Double
    public var notes: String?
    public var createdAt: Date

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        storedReagentClientID: UUID,
        actionType: String,
        quantity: Double,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.storedReagentClientID = storedReagentClientID
        self.actionType = actionType
        self.quantity = quantity
        self.notes = notes
        self.createdAt = createdAt
    }
}
