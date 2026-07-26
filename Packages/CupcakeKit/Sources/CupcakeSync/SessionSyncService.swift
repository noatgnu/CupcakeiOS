import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor SessionSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: SessionStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = SessionStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<SessionDTO> = try await apiClient.get("sessions/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    @discardableResult
    public func createSession(name: String, enabled: Bool = true, protocolServerIDs: [Int64] = []) async throws -> UUID {
        guard let token = deviceToken() else {
            throw SessionSyncError.noDeviceToken
        }
        let dto: SessionDTO = try await apiClient.send(
            "sessions/",
            method: .post,
            body: CreateSessionRequest(name: name, enabled: enabled, protocols: protocolServerIDs),
            authorizationHeader: "DeviceToken \(token)"
        )
        return try await store.upsertOne(dto)
    }

    @discardableResult
    public func syncLocallyCreatedSession(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw SessionSyncError.noDeviceToken
        }
        let fields = try await store.sessionFields(clientID: clientID)
        guard fields.allProtocolsResolved else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: SessionDTO = try await apiClient.send(
            "sessions/",
            method: .post,
            body: CreateSessionRequest(name: fields.name ?? "", enabled: fields.enabled, protocols: fields.resolvedProtocolServerIDs),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func update(serverID: Int64, name: String, enabled: Bool) async throws -> SessionDTO {
        guard let token = deviceToken() else {
            throw SessionSyncError.noDeviceToken
        }
        let dto: SessionDTO = try await apiClient.send(
            "sessions/\(serverID)/",
            method: .patch,
            body: UpdateSessionRequest(name: name, enabled: enabled),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw SessionSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "sessions/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(serverID: serverID)
    }
}

public enum SessionSyncError: Error {
    case noDeviceToken
    case sessionNotCached
}

@ModelActor
actor SessionStore {
    func upsert(_ dtos: [SessionDTO]) throws {
        for dto in dtos {
            _ = upsert(dto)
        }
        try modelContext.save()
    }

    func upsertOne(_ dto: SessionDTO) throws -> UUID {
        let clientID = upsert(dto)
        try modelContext.save()
        return clientID
    }

    func sessionFields(clientID: UUID) throws -> (name: String?, enabled: Bool, resolvedProtocolServerIDs: [Int64], allProtocolsResolved: Bool) {
        guard let session = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionSyncError.sessionNotCached
        }
        var resolvedServerIDs: [Int64] = []
        for protocolClientID in session.protocolClientIDs {
            let match = try? modelContext.fetch(
                FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.clientID == protocolClientID })
            )
            if let serverID = match?.first?.serverID {
                resolvedServerIDs.append(serverID)
            }
        }
        let allResolved = resolvedServerIDs.count == session.protocolClientIDs.count
        return (session.name, session.enabled, resolvedServerIDs, allResolved)
    }

    func attachServerID(clientID: UUID, dto: SessionDTO) throws {
        guard let session = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw SessionSyncError.sessionNotCached
        }
        session.serverID = dto.id
        session.uniqueID = dto.uniqueId
        session.name = dto.name
        session.enabled = dto.enabled
        session.isRunning = dto.isRunning
        if let status = dto.status {
            session.status = status
        }
        session.protocolServerIDs = dto.protocols
        let resolvedClientIDs = protocolClientIDs(forServerIDs: dto.protocols)
        if !resolvedClientIDs.isEmpty {
            session.protocolClientIDs = resolvedClientIDs
        }
        session.primaryProtocolClientID = session.protocolClientIDs.first
        try modelContext.save()
    }

    @discardableResult
    private func upsert(_ dto: SessionDTO) -> UUID {
        let sessionServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == sessionServerID })
        )
        let resolvedClientIDs = protocolClientIDs(forServerIDs: dto.protocols)
        let cachedSession = existing?.first ?? {
            let created = CachedSession(
                serverID: dto.id,
                uniqueID: dto.uniqueId,
                name: dto.name,
                enabled: dto.enabled,
                isRunning: dto.isRunning,
                status: dto.status ?? "draft",
                protocolServerIDs: dto.protocols,
                protocolClientIDs: resolvedClientIDs,
                primaryProtocolClientID: resolvedClientIDs.first,
                createdAt: Date.parsedISO8601(dto.createdAt)
            )
            modelContext.insert(created)
            return created
        }()
        cachedSession.uniqueID = dto.uniqueId
        cachedSession.name = dto.name
        cachedSession.enabled = dto.enabled
        cachedSession.isRunning = dto.isRunning
        if let status = dto.status {
            cachedSession.status = status
        }
        cachedSession.protocolServerIDs = dto.protocols
        if cachedSession.protocolClientIDs.isEmpty {
            cachedSession.protocolClientIDs = resolvedClientIDs
        }
        if cachedSession.primaryProtocolClientID == nil {
            cachedSession.primaryProtocolClientID = cachedSession.protocolClientIDs.first
        }
        return cachedSession.clientID
    }

    func removeLocal(serverID: Int64) throws {
        guard let session = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(session)
        try modelContext.save()
    }

    private func protocolClientIDs(forServerIDs protocolServerIDs: [Int64]) -> [UUID] {
        protocolServerIDs.compactMap { serverID in
            let match = try? modelContext.fetch(
                FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == serverID })
            )
            return match?.first?.clientID
        }
    }
}
