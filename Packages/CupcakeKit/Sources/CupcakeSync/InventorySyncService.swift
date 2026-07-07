import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Full-refetch population of storage/reagent lookup data, plus `StoredReagent`/`ReagentAction` offline create.
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

    /// Live search only, no local caching. For the molarity calculator's molecular-weight typeahead, 2-char minimum.
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

    /// Plain full-refetch every cycle; `ReagentAction` has no delta filter or deletion-log coverage server-side.
    public func refetchReagentActions() async throws {
        try await refetchAllPages(path: "reagent-actions/") { (dtos: [ReagentActionDTO]) in
            try await store.upsertReagentActions(dtos)
        }
    }

    /// Pushes an already locally-created stored-reagent to the server, syncing its reagent inline if needed.
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
                lowStockThreshold: fields.lowStockThreshold
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(storedReagentClientID: clientID, dto: dto)
        return dto.id
    }

    /// Same shape, for a `ReagentAction`. Throws `SyncDependencyError.parentNotSynced` if its stored-reagent hasn't synced yet.
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

    private func refetchAllPages<DTO: Decodable & Sendable>(
        path: String,
        upsert: ([DTO]) async throws -> Void
    ) async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<DTO> = try await apiClient.get(path, authorizationHeader: authorization)
        while true {
            try await upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }
}

public enum InventorySyncError: Error {
    case noDeviceToken
    case storedReagentNotCached
    case reagentActionNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
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
                    storedAtServerID: dto.storedAt
                )
                modelContext.insert(created)
                return created
            }()
            object.objectType = dto.objectType
            object.objectName = dto.objectName
            object.objectDescription = dto.objectDescription
            object.storedAtServerID = dto.storedAt
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
                let created = CachedReagent(serverID: dto.id, name: dto.name, unit: dto.unit)
                modelContext.insert(created)
                return created
            }()
            reagent.name = dto.name
            reagent.unit = dto.unit
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
                    lowStockThreshold: dto.lowStockThreshold
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
        }
        try modelContext.save()
    }

    func upsertReagentActions(_ dtos: [ReagentActionDTO]) throws {
        for dto in dtos {
            // Skip a reagent-action whose stored-reagent isn't cached yet.
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
        lowStockThreshold: Double?
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
            storedReagent.lowStockThreshold
        )
    }

    /// Attaches a newly-assigned `serverID` to the existing local reagent matched by `clientID`.
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

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID`.
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

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID`.
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
