import Foundation
import SwiftData

/// Offline-createable from Phase 3 on. Uses the same client-generated-identity pattern as
/// `CachedSession`/`CachedStepAnnotation` from the start, even though Phase 1 only exercised the
/// read-only cache side, to avoid a schema migration once Phase 3 added the offline-create path.
///
/// A newly locally-created `StoredReagent` is only ever edited via `CachedReagentAction` entries
/// (add/reserve) afterward, never by mutating `quantity`/`currentQuantity` directly — matching
/// `current_quantity`'s server-side status as a read-only `SerializerMethodField` computed from
/// the sum of its actions (§4).
@Model
public final class CachedStoredReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    /// Nullable: `reagent` is a nullable FK on `StoredReagent` server-side, so `reagentName`/
    /// `reagentUnit` (sourced from the related `Reagent`) are also nullable.
    public var reagentServerID: Int64?
    /// The attached reagent's `clientID` — needed to resolve a brand-new, not-yet-synced local
    /// `CachedReagent` (no `serverID` yet) when this record itself gets synced, same reasoning
    /// as `CachedStepReagent.reagentClientID`. `nil` for a stored reagent read straight from the
    /// server (where the reagent, if any, already has a `serverID` and no local-only identity
    /// needs tracking).
    public var reagentClientID: UUID?
    public var reagentName: String?
    public var reagentUnit: String?
    /// Nullable: `storage_object` is *also* a nullable FK server-side (`ccm/models.py:434-439`,
    /// confirmed directly against the model) — an earlier version of this DTO/model wrongly
    /// treated it as non-optional `Int64`, which would have crashed decoding the first time the
    /// server actually returned `storage_object: null`.
    public var storageObjectServerID: Int64?
    public var storageObjectName: String?
    public var quantity: Double
    public var currentQuantity: Double
    public var barcode: String?
    /// Date-only string (`"YYYY-MM-DD"`, Django `DateField`), not a full timestamp.
    public var expirationDate: String?
    public var lowStockThreshold: Double?

    public init(
        clientID: UUID = UUID(),
        serverID: Int64? = nil,
        reagentServerID: Int64? = nil,
        reagentClientID: UUID? = nil,
        reagentName: String? = nil,
        reagentUnit: String? = nil,
        storageObjectServerID: Int64? = nil,
        storageObjectName: String? = nil,
        quantity: Double,
        currentQuantity: Double,
        barcode: String? = nil,
        expirationDate: String? = nil,
        lowStockThreshold: Double? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.reagentServerID = reagentServerID
        self.reagentClientID = reagentClientID
        self.reagentName = reagentName
        self.reagentUnit = reagentUnit
        self.storageObjectServerID = storageObjectServerID
        self.storageObjectName = storageObjectName
        self.quantity = quantity
        self.currentQuantity = currentQuantity
        self.barcode = barcode
        self.expirationDate = expirationDate
        self.lowStockThreshold = lowStockThreshold
    }
}
