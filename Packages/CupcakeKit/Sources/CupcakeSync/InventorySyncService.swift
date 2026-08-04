import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor InventorySyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: InventoryStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = InventoryStore(modelContainer: modelContainer)
    }

    public func refetchStorageObjects() async throws {
        try await refetchAllPages(path: "storage-objects/") { (dtos: [StorageObjectDTO]) in
            try await store.upsertStorageObjects(dtos)
        }
    }

    public func refetchReagents() async throws {
        try await refetchAllPages(path: "reagents/") { (dtos: [ReagentDTO]) in
            try await store.upsertReagents(dtos)
        }
    }

    public func refetchStoredReagents() async throws {
        try await refetchAllPages(path: "stored-reagents/") { (dtos: [StoredReagentDTO]) in
            try await store.upsertStoredReagents(dtos)
        }
    }

    public func searchStoredReagentsWithMolecularWeight(search: String) async throws -> [StoredReagentDTO] {
        guard search.count >= 2, let token = deviceToken() else { return [] }
        let page: PaginatedResponse<StoredReagentDTO> = try await apiClient.get(
            "stored-reagents/",
            query: [
                URLQueryItem(name: "search", value: search),
                URLQueryItem(name: "molecular_weight__isnull", value: "false"),
                URLQueryItem(name: "limit", value: "10"),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results
    }

    @discardableResult
    public func createStorageObject(objectName: String, objectType: String, objectDescription: String?, storedAt: Int64?) async throws -> StorageObjectDTO {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        let dto: StorageObjectDTO = try await apiClient.send(
            "storage-objects/",
            method: .post,
            body: CreateStorageObjectRequest(objectName: objectName, objectType: objectType, objectDescription: objectDescription, storedAt: storedAt),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertStorageObjects([dto])
        return dto
    }

    @discardableResult
    public func updateStorageObject(serverID: Int64, objectName: String, objectType: String, objectDescription: String?) async throws -> StorageObjectDTO {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        let dto: StorageObjectDTO = try await apiClient.send(
            "storage-objects/\(serverID)/",
            method: .patch,
            body: UpdateStorageObjectRequest(objectName: objectName, objectType: objectType, objectDescription: objectDescription),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertStorageObjects([dto])
        return dto
    }

    public func deleteStorageObject(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "storage-objects/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeStorageObjectLocally(serverID: serverID)
    }

    public func refetchReagentActions() async throws {
        try await refetchAllPages(path: "reagent-actions/") { (dtos: [ReagentActionDTO]) in
            try await store.upsertReagentActions(dtos)
        }
    }

    @discardableResult
    public func syncLocallyCreatedStoredReagent(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        let fields = try await store.storedReagentFields(clientID: clientID)
        guard let storageObjectServerID = fields.storageObjectServerID else {
            throw SyncDependencyError.parentNotSynced
        }

        let reagentServerID: Int64
        if let existingReagentServerID = fields.reagentServerID {
            reagentServerID = existingReagentServerID
        } else if let reagentClientID = fields.reagentClientID {
            let reagentDTO: ReagentDTO = try await apiClient.send(
                "reagents/",
                method: .post,
                body: CreateReagentRequest(name: fields.reagentName ?? "", unit: fields.reagentUnit ?? ""),
                authorizationHeader: "DeviceToken \(token)"
            )
            try await store.attachReagentServerID(reagentClientID: reagentClientID, dto: reagentDTO)
            reagentServerID = reagentDTO.id
        } else {
            throw SyncDependencyError.parentNotSynced
        }

        let dto: StoredReagentDTO = try await apiClient.send(
            "stored-reagents/",
            method: .post,
            body: CreateStoredReagentRequest(
                reagent: reagentServerID,
                storageObject: storageObjectServerID,
                quantity: fields.quantity,
                barcode: fields.barcode,
                expirationDate: fields.expirationDate,
                lowStockThreshold: fields.lowStockThreshold,
                molecularWeight: fields.molecularWeight.map { String(format: "%.4f", $0) },
                notes: fields.notes,
                shareable: fields.shareable,
                accessAll: fields.accessAll,
                notifyOnLowStock: fields.notifyOnLowStock,
                pngBase64: fields.pngBase64
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(storedReagentClientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func syncLocallyCreatedReagentAction(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        let fields = try await store.reagentActionFields(clientID: clientID)
        guard let storedReagentServerID = fields.storedReagentServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: ReagentActionDTO = try await apiClient.send(
            "reagent-actions/",
            method: .post,
            body: CreateReagentActionRequest(reagent: storedReagentServerID, actionType: fields.actionType, quantity: fields.quantity, notes: fields.notes),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(reagentActionClientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func refreshMetadataTable(metadataTableServerID: Int64) async throws -> MetadataTableDTO {
        guard let token = deviceToken() else {
            throw InventorySyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"
        let table: MetadataTableDTO = try await apiClient.get("metadata-tables/\(metadataTableServerID)/", authorizationHeader: authorization)
        try await store.upsertMetadataTable(table)
        return table
    }

    private func refetchAllPages<DTO: Decodable & Sendable>(
        path: String,
        upsert: @Sendable ([DTO]) async throws -> Void
    ) async throws {
        guard let token = deviceToken() else { return }
        try await apiClient.fetchAllPages(path: path, authorizationHeader: "DeviceToken \(token)", onPage: upsert)
    }
}

public enum InventorySyncError: Error {
    case noDeviceToken
    case storedReagentNotCached
    case reagentActionNotCached
}

@ModelActor
actor InventoryStore {
    func upsertStorageObjects(_ dtos: [StorageObjectDTO]) throws {
        for dto in dtos {
            let objectID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedStorageObject>(predicate: #Predicate { $0.serverID == objectID })
            )
            let object = existing?.first ?? {
                let created = CachedStorageObject(
                    serverID: dto.id,
                    objectType: dto.objectType,
                    objectName: dto.objectName,
                    objectDescription: dto.objectDescription,
                    storedAtServerID: dto.storedAt,
                    createdAt: Date.parsedISO8601(dto.createdAt)
                )
                modelContext.insert(created)
                return created
            }()
            object.objectType = dto.objectType
            object.objectName = dto.objectName
            object.objectDescription = dto.objectDescription
            object.storedAtServerID = dto.storedAt
            object.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: object.updatedAt)
        }
        try modelContext.save()
    }

    func removeStorageObjectLocally(serverID: Int64) throws {
        guard let object = try modelContext.fetch(
            FetchDescriptor<CachedStorageObject>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(object)
        try modelContext.save()
    }

    func upsertReagents(_ dtos: [ReagentDTO]) throws {
        for dto in dtos {
            let reagentID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.serverID == reagentID })
            )
            let reagent = existing?.first ?? {
                let created = CachedReagent(serverID: dto.id, name: dto.name, unit: dto.unit, createdAt: Date.parsedISO8601(dto.createdAt))
                modelContext.insert(created)
                return created
            }()
            reagent.name = dto.name
            reagent.unit = dto.unit
            reagent.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: reagent.updatedAt)
        }
        try modelContext.save()
    }

    func upsertStoredReagents(_ dtos: [StoredReagentDTO]) throws {
        for dto in dtos {
            let storedReagentID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.serverID == storedReagentID })
            )
            let storedReagent = existing?.first ?? {
                let created = CachedStoredReagent(
                    serverID: dto.id,
                    reagentServerID: dto.reagent,
                    reagentName: dto.reagentName,
                    reagentUnit: dto.reagentUnit,
                    storageObjectServerID: dto.storageObject,
                    storageObjectName: dto.storageObjectName,
                    quantity: dto.quantity,
                    currentQuantity: dto.currentQuantity,
                    barcode: dto.barcode,
                    expirationDate: dto.expirationDate,
                    lowStockThreshold: dto.lowStockThreshold,
                    molecularWeight: dto.molecularWeight.flatMap(Double.init),
                    notes: dto.notes,
                    shareable: dto.shareable,
                    accessAll: dto.accessAll,
                    notifyOnLowStock: dto.notifyOnLowStock,
                    pngBase64: dto.pngBase64,
                    metadataTableServerID: dto.metadataTableId,
                    createdAt: Date.parsedISO8601(dto.createdAt)
                )
                modelContext.insert(created)
                return created
            }()
            storedReagent.reagentServerID = dto.reagent
            storedReagent.reagentName = dto.reagentName
            storedReagent.reagentUnit = dto.reagentUnit
            storedReagent.storageObjectServerID = dto.storageObject
            storedReagent.storageObjectName = dto.storageObjectName
            storedReagent.quantity = dto.quantity
            storedReagent.currentQuantity = dto.currentQuantity
            storedReagent.barcode = dto.barcode
            storedReagent.expirationDate = dto.expirationDate
            storedReagent.lowStockThreshold = dto.lowStockThreshold
            storedReagent.molecularWeight = dto.molecularWeight.flatMap(Double.init)
            storedReagent.notes = dto.notes
            storedReagent.shareable = dto.shareable
            storedReagent.accessAll = dto.accessAll
            storedReagent.notifyOnLowStock = dto.notifyOnLowStock
            storedReagent.pngBase64 = dto.pngBase64
            storedReagent.metadataTableServerID = dto.metadataTableId
            storedReagent.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: storedReagent.updatedAt)
        }
        try modelContext.save()
    }

    func upsertMetadataTable(_ dto: MetadataTableDTO) throws {
        let tableServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedMetadataTable>(predicate: #Predicate { $0.serverID == tableServerID })
        )
        let table = existing?.first ?? {
            let created = CachedMetadataTable(serverID: dto.id, name: dto.name)
            modelContext.insert(created)
            return created
        }()
        table.name = dto.name
        table.tableDescription = dto.description
        table.sampleCount = dto.sampleCount
        table.version = dto.version
        table.ownerUsername = dto.ownerUsername
        table.labGroupName = dto.labGroupName
        table.isPublished = dto.isPublished
        table.canEdit = dto.canEdit

        let existingColumns = try? modelContext.fetch(
            FetchDescriptor<CachedMetadataColumn>(predicate: #Predicate { $0.metadataTableServerID == tableServerID })
        )
        for column in existingColumns ?? [] {
            modelContext.delete(column)
        }
        for columnDTO in dto.columns {
            let column = CachedMetadataColumn(
                serverID: columnDTO.id,
                metadataTableServerID: dto.id,
                name: columnDTO.name,
                displayName: columnDTO.displayName,
                type: columnDTO.type,
                columnPosition: columnDTO.columnPosition ?? 0,
                value: columnDTO.value,
                notApplicable: columnDTO.notApplicable,
                notAvailable: columnDTO.notAvailable,
                mandatory: columnDTO.mandatory,
                hidden: columnDTO.hidden,
                readonly: columnDTO.readonly,
                ontologyType: columnDTO.ontologyType,
                staffOnly: columnDTO.staffOnly,
                modifiers: columnDTO.modifiers.map { MetadataColumnModifier(samples: $0.samples, value: $0.value) }
            )
            modelContext.insert(column)
        }
        try modelContext.save()
    }

    func upsertReagentActions(_ dtos: [ReagentActionDTO]) throws {
        for dto in dtos {
            let storedReagentServerID = dto.reagent
            guard let storedReagent = try? modelContext.fetch(
                FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.serverID == storedReagentServerID })
            ).first else { continue }

            let actionID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedReagentAction>(predicate: #Predicate { $0.serverID == actionID })
            )
            let action = existing?.first ?? {
                let created = CachedReagentAction(
                    serverID: dto.id,
                    storedReagentClientID: storedReagent.clientID,
                    actionType: dto.actionType,
                    quantity: dto.quantity,
                    notes: dto.notes
                )
                modelContext.insert(created)
                return created
            }()
            action.storedReagentClientID = storedReagent.clientID
            action.actionType = dto.actionType
            action.quantity = dto.quantity
            action.notes = dto.notes
        }
        try modelContext.save()
    }

    func storedReagentFields(clientID: UUID) throws -> (
        reagentServerID: Int64?,
        reagentClientID: UUID?,
        reagentName: String?,
        reagentUnit: String?,
        storageObjectServerID: Int64?,
        quantity: Double,
        barcode: String?,
        expirationDate: String?,
        lowStockThreshold: Double?,
        molecularWeight: Double?,
        notes: String?,
        shareable: Bool,
        accessAll: Bool,
        notifyOnLowStock: Bool,
        pngBase64: String?
    ) {
        guard let storedReagent = try modelContext.fetch(
            FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw InventorySyncError.storedReagentNotCached
        }
        return (
            storedReagent.reagentServerID,
            storedReagent.reagentClientID,
            storedReagent.reagentName,
            storedReagent.reagentUnit,
            storedReagent.storageObjectServerID,
            storedReagent.quantity,
            storedReagent.barcode,
            storedReagent.expirationDate,
            storedReagent.lowStockThreshold,
            storedReagent.molecularWeight,
            storedReagent.notes,
            storedReagent.shareable,
            storedReagent.accessAll,
            storedReagent.notifyOnLowStock,
            storedReagent.pngBase64
        )
    }

    func attachReagentServerID(reagentClientID: UUID, dto: ReagentDTO) throws {
        guard let reagent = try modelContext.fetch(
            FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.clientID == reagentClientID })
        ).first else {
            throw InventorySyncError.storedReagentNotCached
        }
        reagent.serverID = dto.id
        reagent.name = dto.name
        reagent.unit = dto.unit
        try modelContext.save()
    }

    func attachServerID(storedReagentClientID: UUID, dto: StoredReagentDTO) throws {
        guard let storedReagent = try modelContext.fetch(
            FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.clientID == storedReagentClientID })
        ).first else {
            throw InventorySyncError.storedReagentNotCached
        }
        storedReagent.serverID = dto.id
        storedReagent.reagentServerID = dto.reagent
        storedReagent.reagentName = dto.reagentName
        storedReagent.reagentUnit = dto.reagentUnit
        storedReagent.storageObjectServerID = dto.storageObject
        storedReagent.storageObjectName = dto.storageObjectName
        storedReagent.quantity = dto.quantity
        storedReagent.currentQuantity = dto.currentQuantity
        storedReagent.barcode = dto.barcode
        storedReagent.expirationDate = dto.expirationDate
        storedReagent.lowStockThreshold = dto.lowStockThreshold
        storedReagent.molecularWeight = dto.molecularWeight.flatMap(Double.init)
        storedReagent.notes = dto.notes
        storedReagent.shareable = dto.shareable
        storedReagent.accessAll = dto.accessAll
        storedReagent.notifyOnLowStock = dto.notifyOnLowStock
        storedReagent.pngBase64 = dto.pngBase64
        storedReagent.metadataTableServerID = dto.metadataTableId
        try modelContext.save()
    }

    func reagentActionFields(clientID: UUID) throws -> (storedReagentServerID: Int64?, actionType: String, quantity: Double, notes: String?) {
        guard let action = try modelContext.fetch(
            FetchDescriptor<CachedReagentAction>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw InventorySyncError.reagentActionNotCached
        }
        let storedReagentClientID = action.storedReagentClientID
        let storedReagent = try modelContext.fetch(
            FetchDescriptor<CachedStoredReagent>(predicate: #Predicate { $0.clientID == storedReagentClientID })
        ).first
        return (storedReagent?.serverID, action.actionType, action.quantity, action.notes)
    }

    func attachServerID(reagentActionClientID: UUID, dto: ReagentActionDTO) throws {
        guard let action = try modelContext.fetch(
            FetchDescriptor<CachedReagentAction>(predicate: #Predicate { $0.clientID == reagentActionClientID })
        ).first else {
            throw InventorySyncError.reagentActionNotCached
        }
        action.serverID = dto.id
        action.actionType = dto.actionType
        action.quantity = dto.quantity
        action.notes = dto.notes
        try modelContext.save()
    }
}
