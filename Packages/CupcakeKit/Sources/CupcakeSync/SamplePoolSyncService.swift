import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor SamplePoolSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: SamplePoolStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = SamplePoolStore(modelContainer: modelContainer)
    }

    public func refetch(metadataTableServerID: Int64) async throws {
        guard let token = deviceToken() else { return }
        try await apiClient.fetchAllPages(
            path: "sample-pools/",
            query: [URLQueryItem(name: "metadata_table_id", value: String(metadataTableServerID))],
            authorizationHeader: "DeviceToken \(token)"
        ) { (dtos: [SamplePoolDTO]) in
            try await store.upsert(dtos)
        }
    }

    public func fetchDetail(metadataTableServerID: Int64) async throws -> [SamplePoolDTO] {
        guard let token = deviceToken() else { return [] }
        return try await apiClient.fetchAllPages(
            path: "sample-pools/",
            query: [URLQueryItem(name: "metadata_table_id", value: String(metadataTableServerID))],
            authorizationHeader: "DeviceToken \(token)"
        )
    }

    @discardableResult
    public func create(
        metadataTableServerID: Int64,
        poolName: String,
        poolDescription: String?,
        pooledOnlySamples: [Int],
        pooledAndIndependentSamples: [Int],
        isReference: Bool
    ) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw SamplePoolSyncError.noDeviceToken
        }
        let dto: SamplePoolDTO = try await apiClient.send(
            "sample-pools/",
            method: .post,
            body: CreateSamplePoolRequest(
                metadataTable: metadataTableServerID,
                poolName: poolName,
                poolDescription: poolDescription,
                pooledOnlySamples: pooledOnlySamples,
                pooledAndIndependentSamples: pooledAndIndependentSamples,
                isReference: isReference
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto.id
    }

    @discardableResult
    public func update(
        serverID: Int64,
        poolName: String,
        poolDescription: String?,
        pooledOnlySamples: [Int],
        pooledAndIndependentSamples: [Int],
        isReference: Bool
    ) async throws -> SamplePoolDTO {
        guard let token = deviceToken() else {
            throw SamplePoolSyncError.noDeviceToken
        }
        let dto: SamplePoolDTO = try await apiClient.send(
            "sample-pools/\(serverID)/",
            method: .patch,
            body: UpdateSamplePoolRequest(
                poolName: poolName,
                poolDescription: poolDescription,
                pooledOnlySamples: pooledOnlySamples,
                pooledAndIndependentSamples: pooledAndIndependentSamples,
                isReference: isReference
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw SamplePoolSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("sample-pools/\(serverID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.removeLocal(serverID: serverID)
    }
}

public enum SamplePoolSyncError: Error {
    case noDeviceToken
}

actor SamplePoolStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsert(_ dtos: [SamplePoolDTO]) throws {
        for dto in dtos {
            try upsertSingle(dto)
        }
    }

    func upsertSingle(_ dto: SamplePoolDTO) throws {
        let serverID = dto.id
        if let existing = try modelContext.fetch(FetchDescriptor<CachedSamplePool>(predicate: #Predicate { $0.serverID == serverID })).first {
            existing.metadataTableServerID = dto.metadataTable
            existing.poolName = dto.poolName
            existing.poolDescription = dto.poolDescription
            existing.pooledOnlySamples = dto.pooledOnlySamples
            existing.pooledAndIndependentSamples = dto.pooledAndIndependentSamples
            existing.isReference = dto.isReference
            existing.sdrfValue = dto.sdrfValue
            existing.totalSamples = dto.totalSamples ?? existing.totalSamples
        } else {
            modelContext.insert(CachedSamplePool(
                serverID: dto.id,
                metadataTableServerID: dto.metadataTable,
                poolName: dto.poolName,
                poolDescription: dto.poolDescription,
                pooledOnlySamples: dto.pooledOnlySamples,
                pooledAndIndependentSamples: dto.pooledAndIndependentSamples,
                isReference: dto.isReference,
                sdrfValue: dto.sdrfValue,
                totalSamples: dto.totalSamples ?? 0
            ))
        }
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let existing = try modelContext.fetch(FetchDescriptor<CachedSamplePool>(predicate: #Predicate { $0.serverID == serverID })).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
