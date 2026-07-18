import Foundation
import SwiftData

@Model
public final class CachedStoredReagent {
    @Attribute(.unique) public var clientID: UUID
    public var serverID: Int64?
    public var reagentServerID: Int64?
    public var reagentClientID: UUID?
    public var reagentName: String?
    public var reagentUnit: String?
    public var storageObjectServerID: Int64?
    public var storageObjectName: String?
    public var quantity: Double
    public var currentQuantity: Double
    public var barcode: String?
    public var expirationDate: String?
    public var lowStockThreshold: Double?
    public var molecularWeight: Double?
    public var notes: String?
    public var shareable: Bool
    public var accessAll: Bool
    public var notifyOnLowStock: Bool
    public var pngBase64: String?
    public var metadataTableServerID: Int64?
    public var createdAt: Date
    public var updatedAt: Date

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
        lowStockThreshold: Double? = nil,
        molecularWeight: Double? = nil,
        notes: String? = nil,
        shareable: Bool = false,
        accessAll: Bool = false,
        notifyOnLowStock: Bool = false,
        pngBase64: String? = nil,
        metadataTableServerID: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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
        self.molecularWeight = molecularWeight
        self.notes = notes
        self.shareable = shareable
        self.accessAll = accessAll
        self.notifyOnLowStock = notifyOnLowStock
        self.pngBase64 = pngBase64
        self.metadataTableServerID = metadataTableServerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
