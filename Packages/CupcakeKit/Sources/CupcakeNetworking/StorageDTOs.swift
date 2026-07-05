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
/// scope needs it yet. `reagent` **and** `storage_object` are both nullable FKs
/// (`ccm/models.py:434-439` — `blank=True, null=True` on both, confirmed directly against the
/// model, not assumed from the serializer), so `reagentName`/`reagentUnit`/`storageObjectName`
/// (all sourced from the related objects) must be optional too, since there's no related object
/// to read them from when the FK is null. `expirationDate` is a `DateField` (date-only,
/// `"YYYY-MM-DD"`), not a full timestamp — don't parse it with an ISO8601-with-time formatter.
public struct StoredReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let reagent: Int64?
    public let reagentName: String?
    public let reagentUnit: String?
    public let storageObject: Int64?
    public let storageObjectName: String?
    public let quantity: Double
    public let currentQuantity: Double
    public let barcode: String?
    public let expirationDate: String?
    public let lowStockThreshold: Double?
}

/// `POST stored-reagents/` body. Field set verified against `StoredReagentSerializer`
/// (`ccm/serializers.py:648-675`) and the reference web app's `stored-reagent-create-modal.ts`
/// (fields 28-39): despite both `reagent`/`storage_object` being nullable at the model layer,
/// this app always supplies both when creating from a specific storage location with a resolved
/// reagent — reproducing "create with neither" isn't a real flow the reference UI exposes.
/// `reagent` must already exist server-side (a plain `PrimaryKeyRelatedField`, no inline/nested
/// create) — see `AttachReagentSheet`'s same reagent-resolution pattern.
public struct CreateStoredReagentRequest: Encodable, Sendable {
    public var reagent: Int64
    public var storageObject: Int64
    public var quantity: Double
    public var barcode: String?
    public var expirationDate: String?
    public var lowStockThreshold: Double?

    public init(reagent: Int64, storageObject: Int64, quantity: Double, barcode: String?, expirationDate: String?, lowStockThreshold: Double?) {
        self.reagent = reagent
        self.storageObject = storageObject
        self.quantity = quantity
        self.barcode = barcode
        self.expirationDate = expirationDate
        self.lowStockThreshold = lowStockThreshold
    }
}

/// `POST reagent-actions/` body. Field set verified against `ReagentActionSerializer`
/// (`ccm/serializers.py:1498-1558`) — `reagent` here is the **`StoredReagent`** FK (a
/// same-named-but-different relationship from `ReagentDTO`/`Reagent`, confirmed against
/// `ccm/models.py:705`), not the catalog `Reagent`. `actionType` is one of exactly `"add"`/
/// `"reserve"` — there is no `"consume"` choice anywhere in the backend
/// (`action_type_choices`, `ccm/models.py:700-703`), despite that being an intuitive guess.
/// `quantity` must be `> 0` server-side regardless of `actionType` — the add/subtract sign is
/// implied by `actionType`, not by the sign of `quantity` itself.
public struct CreateReagentActionRequest: Encodable, Sendable {
    public var reagent: Int64
    public var actionType: String
    public var quantity: Double
    public var notes: String?

    public init(reagent: Int64, actionType: String, quantity: Double, notes: String?) {
        self.reagent = reagent
        self.actionType = actionType
        self.quantity = quantity
        self.notes = notes
    }
}

/// `GET reagent-actions/` response shape — read-only for this app; a `ReagentAction` is only
/// ever created through `CreateReagentActionRequest`, never edited or deleted locally.
public struct ReagentActionDTO: Decodable, Sendable {
    public let id: Int64
    public let reagent: Int64
    public let actionType: String
    public let quantity: Double
    public let notes: String?
}
