import Foundation
import SwiftData

/// Offline-createable from Phase 3 on (net-new stock entries only — editing an existing cached
/// `StoredReagent`'s quantity offline is disallowed by design, §4). Uses the same
/// client-generated-identity pattern as `CachedSession`/`CachedStepAnnotation` from the start,
/// even though Phase 1 only exercises the read-only cache side, to avoid a schema migration once
/// Phase 3 adds the offline-create path.
@Model
public final class CachedStoredReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    /// Nullable: `reagent` is a nullable FK on `StoredReagent` server-side, so `reagentName`/
    /// `reagentUnit` (sourced from the related `Reagent`) are also nullable.
    public var reagentServerID: Int64?
    public var reagentName: String?
    public var reagentUnit: String?
    public var storageObjectServerID: Int64
    public var storageObjectName: String
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
        reagentName: String? = nil,
        reagentUnit: String? = nil,
        storageObjectServerID: Int64,
        storageObjectName: String,
        quantity: Double,
        currentQuantity: Double,
        barcode: String? = nil,
        expirationDate: String? = nil,
        lowStockThreshold: Double? = nil
    ) {
        self.clientID = clientID
        self.serverID = serverID
        self.reagentServerID = reagentServerID
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
