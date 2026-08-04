import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor StepVariationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: StepVariationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = StepVariationStore(modelContainer: modelContainer)
    }

    public func refetch(stepServerID: Int64, sessionServerID: Int64? = nil) async throws {
        guard let token = deviceToken() else { return }
        var query = [URLQueryItem(name: "step", value: String(stepServerID))]
        if let sessionServerID {
            query.append(URLQueryItem(name: "session", value: String(sessionServerID)))
        }
        try await apiClient.fetchAllPages(
            path: "step-variations/",
            query: query,
            authorizationHeader: "DeviceToken \(token)"
        ) { (dtos: [StepVariationDTO]) in
            try await store.upsert(dtos)
        }
    }

    @discardableResult
    public func create(
        stepServerID: Int64,
        sessionServerID: Int64? = nil,
        variationDescription: String,
        variationDuration: Int
    ) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StepVariationSyncError.noDeviceToken
        }
        let dto: StepVariationDTO = try await apiClient.send(
            "step-variations/",
            method: .post,
            body: CreateStepVariationRequest(
                step: stepServerID,
                session: sessionServerID,
                variationDescription: variationDescription,
                variationDuration: variationDuration
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto.id
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw StepVariationSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("step-variations/\(serverID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.removeLocal(serverID: serverID)
    }
}

public enum StepVariationSyncError: Error {
    case noDeviceToken
}

actor StepVariationStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsert(_ dtos: [StepVariationDTO]) throws {
        for dto in dtos {
            try upsertSingle(dto)
        }
    }

    func upsertSingle(_ dto: StepVariationDTO) throws {
        let serverID = dto.id
        if let existing = try modelContext.fetch(FetchDescriptor<CachedStepVariation>(predicate: #Predicate { $0.serverID == serverID })).first {
            existing.stepServerID = dto.step
            existing.sessionServerID = dto.session
            existing.variationDescription = dto.variationDescription
            existing.variationDuration = dto.variationDuration
        } else {
            modelContext.insert(CachedStepVariation(
                serverID: dto.id,
                stepServerID: dto.step,
                sessionServerID: dto.session,
                variationDescription: dto.variationDescription,
                variationDuration: dto.variationDuration
            ))
        }
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let existing = try modelContext.fetch(FetchDescriptor<CachedStepVariation>(predicate: #Predicate { $0.serverID == serverID })).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
