import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch, read-only population of storage/reagent lookup data. Offline create
/// for `StoredReagent`/`ReagentAction` is Phase 3.
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
}
