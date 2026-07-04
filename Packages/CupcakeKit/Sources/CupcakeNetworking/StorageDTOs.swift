/// Field names verified directly against `ccm/serializers.py`'s `StorageObjectSerializer`,
/// `ReagentSerializer`, `StoredReagentSerializer`. Read-only for Phase 1 — offline create for
/// `StoredReagent`/`ReagentAction` lands in Phase 3.
public struct StorageObjectDTO: Decodable, Sendable {
    public let id: Int64
    public let objectType: String
    public let objectName: String
    public let objectDescription: String?
    public let storedAt: Int64?
}

public struct ReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let unit: String
}

/// `molecular_weight` is deliberately omitted — it's a Django `DecimalField`, which DRF
/// serializes as a string by default (not a bare JSON number), and nothing in this app's v1
/// scope needs it yet. `reagent` is a nullable FK (`ccm/models.py`), so `reagentName`/
/// `reagentUnit` — sourced from `reagent.name`/`reagent.unit` — must be optional too, since
/// there's no related object to read them from when it's null. `expirationDate` is a `DateField`
/// (date-only, `"YYYY-MM-DD"`), not a full timestamp — don't parse it with an ISO8601-with-time
/// formatter.
public struct StoredReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let reagent: Int64?
    public let reagentName: String?
    public let reagentUnit: String?
    public let storageObject: Int64
    public let storageObjectName: String
    public let quantity: Double
    public let currentQuantity: Double
    public let barcode: String?
    public let expirationDate: String?
    public let lowStockThreshold: Double?
}
