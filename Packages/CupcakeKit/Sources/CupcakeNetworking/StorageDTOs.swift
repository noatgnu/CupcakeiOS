public struct StorageObjectDTO: Decodable, Sendable {
    public let id: Int64
    public let objectType: String
    public let objectName: String
    public let objectDescription: String?
    public let storedAt: Int64?
    public let createdAt: String?
    public let updatedAt: String?
}

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
    public let createdAt: String?
    public let updatedAt: String?
}

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
    public let notes: String?
    public let shareable: Bool
    public let accessAll: Bool
    public let notifyOnLowStock: Bool
    public let pngBase64: String?
    public let metadataTableId: Int64?
    public let metadataTableName: String?
    public let createdAt: String?
    public let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, reagent, reagentName, reagentUnit, storageObject, storageObjectName
        case quantity, currentQuantity, barcode, expirationDate, lowStockThreshold
        case molecularWeight, notes, shareable, accessAll, notifyOnLowStock, pngBase64
        case metadataTableId, metadataTableName, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        reagent = try container.decodeIfPresent(Int64.self, forKey: .reagent)
        reagentName = try container.decodeIfPresent(String.self, forKey: .reagentName)
        reagentUnit = try container.decodeIfPresent(String.self, forKey: .reagentUnit)
        storageObject = try container.decodeIfPresent(Int64.self, forKey: .storageObject)
        storageObjectName = try container.decodeIfPresent(String.self, forKey: .storageObjectName)
        quantity = try container.decode(Double.self, forKey: .quantity)
        currentQuantity = try container.decode(Double.self, forKey: .currentQuantity)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        expirationDate = try container.decodeIfPresent(String.self, forKey: .expirationDate)
        lowStockThreshold = try container.decodeIfPresent(Double.self, forKey: .lowStockThreshold)
        molecularWeight = try container.decodeIfPresent(String.self, forKey: .molecularWeight)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        shareable = try container.decodeIfPresent(Bool.self, forKey: .shareable) ?? false
        accessAll = try container.decodeIfPresent(Bool.self, forKey: .accessAll) ?? false
        notifyOnLowStock = try container.decodeIfPresent(Bool.self, forKey: .notifyOnLowStock) ?? false
        pngBase64 = try container.decodeIfPresent(String.self, forKey: .pngBase64)
        metadataTableId = try container.decodeIfPresent(Int64.self, forKey: .metadataTableId)
        metadataTableName = try container.decodeIfPresent(String.self, forKey: .metadataTableName)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

public struct CreateStoredReagentRequest: Encodable, Sendable {
    public var reagent: Int64
    public var storageObject: Int64
    public var quantity: Double
    public var barcode: String?
    public var expirationDate: String?
    public var lowStockThreshold: Double?
    public var molecularWeight: String?
    public var notes: String?
    public var shareable: Bool
    public var accessAll: Bool
    public var notifyOnLowStock: Bool
    public var pngBase64: String?

    public init(
        reagent: Int64,
        storageObject: Int64,
        quantity: Double,
        barcode: String?,
        expirationDate: String?,
        lowStockThreshold: Double?,
        molecularWeight: String? = nil,
        notes: String? = nil,
        shareable: Bool = false,
        accessAll: Bool = false,
        notifyOnLowStock: Bool = false,
        pngBase64: String? = nil
    ) {
        self.reagent = reagent
        self.storageObject = storageObject
        self.quantity = quantity
        self.barcode = barcode
        self.expirationDate = expirationDate
        self.lowStockThreshold = lowStockThreshold
        self.molecularWeight = molecularWeight
        self.notes = notes
        self.shareable = shareable
        self.accessAll = accessAll
        self.notifyOnLowStock = notifyOnLowStock
        self.pngBase64 = pngBase64
    }
}

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

public struct ReagentActionDTO: Decodable, Sendable {
    public let id: Int64
    public let reagent: Int64
    public let actionType: String
    public let quantity: Double
    public let notes: String?
}
