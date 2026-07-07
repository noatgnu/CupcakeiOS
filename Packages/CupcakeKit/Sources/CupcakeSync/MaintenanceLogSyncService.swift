import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Instrument maintenance logs. Online-only, requiring server-checked `can_manage` permission.
public actor MaintenanceLogSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: MaintenanceLogStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = MaintenanceLogStore(modelContainer: modelContainer)
    }

    public func refetch(instrumentServerID: Int64) async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"
        var page: PaginatedResponse<MaintenanceLogDTO> = try await apiClient.get(
            "maintenance-logs/",
            query: [URLQueryItem(name: "instrument", value: String(instrumentServerID))],
            authorizationHeader: authorization
        )
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    @discardableResult
    public func create(
        instrumentServerID: Int64,
        maintenanceDate: String?,
        maintenanceType: String,
        status: String,
        maintenanceDescription: String?,
        maintenanceNotes: String?
    ) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw MaintenanceLogSyncError.noDeviceToken
        }
        let dto: MaintenanceLogDTO = try await apiClient.send(
            "maintenance-logs/",
            method: .post,
            body: CreateMaintenanceLogRequest(
                instrument: instrumentServerID,
                maintenanceDate: maintenanceDate,
                maintenanceType: maintenanceType,
                status: status,
                maintenanceDescription: maintenanceDescription,
                maintenanceNotes: maintenanceNotes
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto.id
    }

    @discardableResult
    public func updateStatus(serverID: Int64, status: String) async throws -> MaintenanceLogDTO {
        guard let token = deviceToken() else {
            throw MaintenanceLogSyncError.noDeviceToken
        }
        let dto: MaintenanceLogDTO = try await apiClient.send(
            "maintenance-logs/\(serverID)/",
            method: .patch,
            body: UpdateMaintenanceLogStatusRequest(status: status),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw MaintenanceLogSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent("maintenance-logs/\(serverID)/", method: .delete, authorizationHeader: "DeviceToken \(token)")
        try await store.removeLocal(serverID: serverID)
    }
}

public enum MaintenanceLogSyncError: Error {
    case noDeviceToken
}

actor MaintenanceLogStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func upsert(_ dtos: [MaintenanceLogDTO]) throws {
        for dto in dtos {
            try upsertSingle(dto)
        }
    }

    func upsertSingle(_ dto: MaintenanceLogDTO) throws {
        let serverID = dto.id
        if let existing = try modelContext.fetch(FetchDescriptor<CachedMaintenanceLog>(predicate: #Predicate { $0.serverID == serverID })).first {
            existing.instrumentServerID = dto.instrument
            existing.instrumentName = dto.instrumentName ?? existing.instrumentName
            existing.maintenanceDate = dto.maintenanceDate
            existing.maintenanceType = dto.maintenanceType
            existing.status = dto.status
            existing.maintenanceDescription = dto.maintenanceDescription
            existing.maintenanceNotes = dto.maintenanceNotes
            existing.isTemplate = dto.isTemplate
        } else {
            modelContext.insert(CachedMaintenanceLog(
                serverID: dto.id,
                instrumentServerID: dto.instrument,
                instrumentName: dto.instrumentName ?? "",
                maintenanceDate: dto.maintenanceDate,
                maintenanceType: dto.maintenanceType,
                status: dto.status,
                maintenanceDescription: dto.maintenanceDescription,
                maintenanceNotes: dto.maintenanceNotes,
                isTemplate: dto.isTemplate
            ))
        }
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let existing = try modelContext.fetch(FetchDescriptor<CachedMaintenanceLog>(predicate: #Predicate { $0.serverID == serverID })).first else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }
}
