import Foundation
import SwiftData

/// Offline-createable. Edited only via `CachedReagentAction` entries afterward, never by mutating quantity directly.
@Model
public final class CachedStoredReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    /// Nullable: `reagent` is a nullable FK on `StoredReagent` server-side.
    public var reagentServerID: Int64?
    /// The attached reagent's `clientID`, for resolving a brand-new, not-yet-synced local `CachedReagent`.
    public var reagentClientID: UUID?
    public var reagentName: String?
    public var reagentUnit: String?
    /// Nullable: `storage_object` is also a nullable FK server-side.
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
