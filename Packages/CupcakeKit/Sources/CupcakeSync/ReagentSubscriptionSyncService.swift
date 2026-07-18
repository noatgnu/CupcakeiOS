import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor ReagentSubscriptionSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: ReagentSubscriptionStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = ReagentSubscriptionStore(modelContainer: modelContainer)
    }

    public func refetchMySubscription(storedReagentServerID: Int64, userID: Int64) async throws {
        guard let token = deviceToken() else { return }
        let page: PaginatedResponse<ReagentSubscriptionDTO> = try await apiClient.get(
            "reagent-subscriptions/",
            query: [
                URLQueryItem(name: "stored_reagent", value: String(storedReagentServerID)),
                URLQueryItem(name: "user", value: String(userID)),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
        guard let dto = page.results.first else { return }
        try await store.upsertSingle(dto)
    }

    @discardableResult
    public func subscribe(
        storedReagentServerID: Int64,
        userID: Int64,
        notifyOnLowStock: Bool,
        notifyOnExpiry: Bool
    ) async throws -> ReagentSubscriptionDTO {
        guard let token = deviceToken() else {
            throw ReagentSubscriptionSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"

        let existing: PaginatedResponse<ReagentSubscriptionDTO> = try await apiClient.get(
            "reagent-subscriptions/",
            query: [
                URLQueryItem(name: "stored_reagent", value: String(storedReagentServerID)),
                URLQueryItem(name: "user", value: String(userID)),
            ],
            authorizationHeader: authorization
        )

        let dto: ReagentSubscriptionDTO
        if let existingSubscription = existing.results.first {
            dto = try await apiClient.send(
                "reagent-subscriptions/\(existingSubscription.id)/",
                method: .patch,
                body: UpdateReagentSubscriptionRequest(notifyOnLowStock: notifyOnLowStock, notifyOnExpiry: notifyOnExpiry),
                authorizationHeader: authorization
            )
        } else {
            dto = try await apiClient.send(
                "reagent-subscriptions/",
                method: .post,
                body: CreateReagentSubscriptionRequest(user: userID, storedReagent: storedReagentServerID, notifyOnLowStock: notifyOnLowStock, notifyOnExpiry: notifyOnExpiry),
                authorizationHeader: authorization
            )
        }
        try await store.upsertSingle(dto)
        return dto
    }

    public func unsubscribe(serverID: Int64, storedReagentServerID: Int64) async throws {
        guard let token = deviceToken() else {
            throw ReagentSubscriptionSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("reagent-subscriptions/\(serverID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.removeLocal(storedReagentServerID: storedReagentServerID)
    }
}

public enum ReagentSubscriptionSyncError: Error {
    case noDeviceToken
}

actor ReagentSubscriptionStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsertSingle(_ dto: ReagentSubscriptionDTO) throws {
        let storedReagentServerID = dto.storedReagent
        if let existing = try modelContext.fetch(FetchDescriptor<CachedReagentSubscription>(predicate: #Predicate { $0.storedReagentServerID == storedReagentServerID })).first {
            existing.serverID = dto.id
            existing.notifyOnLowStock = dto.notifyOnLowStock
            existing.notifyOnExpiry = dto.notifyOnExpiry
        } else {
            modelContext.insert(CachedReagentSubscription(
                storedReagentServerID: dto.storedReagent,
                serverID: dto.id,
                notifyOnLowStock: dto.notifyOnLowStock,
                notifyOnExpiry: dto.notifyOnExpiry
            ))
        }
        try modelContext.save()
    }

    func removeLocal(storedReagentServerID: Int64) throws {
        guard let existing = try modelContext.fetch(FetchDescriptor<CachedReagentSubscription>(predicate: #Predicate { $0.storedReagentServerID == storedReagentServerID })).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
