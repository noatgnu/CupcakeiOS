/// `GET storage-objects/` response shape.
public struct StorageObjectDTO: Decodable, Sendable {
    public let id: Int64
    public let objectType: String
    public let objectName: String
    public let objectDescription: String?
    public let storedAt: Int64?
}

/// `POST storage-objects/` body. `objectType` is one of shelf/box/fridge/freezer/room/building/floor/other.
public struct CreateStorageObjectRequest: Encodable, Sendable {
    public var objectName: String
    public var objectType: String
    public var objectDescription: String?
    public var storedAt: Int64?

    public init(objectName: String, objectType: String, objectDescription: String? = nil, storedAt: Int64? = nil) {
        self.objectName = objectName
        self.objectType = objectType
        self.objectDescription = objectDescription
        self.storedAt = storedAt
    }
}

/// `PATCH storage-objects/{id}/` body.
public struct UpdateStorageObjectRequest: Encodable, Sendable {
    public var objectName: String
    public var objectType: String
    public var objectDescription: String?

    public init(objectName: String, objectType: String, objectDescription: String? = nil) {
        self.objectName = objectName
        self.objectType = objectType
        self.objectDescription = objectDescription
    }
}

public struct ReagentDTO: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let unit: String
}

/// `reagent`/`storageObject` are both nullable FKs. `expirationDate` is date-only. `molecularWeight` is a `DecimalField`, serialized as a string.
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
    public let molecularWeight: String?
}

/// `POST stored-reagents/` body. `reagent` must already exist server-side (no inline/nested create).
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

/// `POST reagent-actions/` body. `reagent` here is the `StoredReagent` FK, not the catalog `Reagent`. `actionType` is "add" or "reserve" only.
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

/// `GET reagent-actions/` response shape. Read-only; never edited or deleted locally.
public struct ReagentActionDTO: Decodable, Sendable {
    public let id: Int64
    public let reagent: Int64
    public let actionType: String
    public let quantity: Double
    public let notes: String?
}
