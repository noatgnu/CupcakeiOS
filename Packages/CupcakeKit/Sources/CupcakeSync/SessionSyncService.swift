import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch read cache + a synchronous online-only create. `Session.unique_id` is
/// server-generated (`SessionCreateSerializer.create()` overrides any client-supplied value), so
/// there's no client-identity reconciliation to do here — unlike Phase 2's offline create, this
/// path always has connectivity and gets the real `serverID` back immediately.
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

    /// Requires connectivity — Phase 2 adds the offline-create/outbox path for this. Returns the
    /// new session's `clientID` rather than the cached `@Model` instance — a SwiftData model
    /// object belongs to the actor's own `ModelContext` and can't safely cross to a caller on a
    /// different actor (e.g. the UI's `@MainActor` context); callers re-query their own context
    /// by this ID instead. `clientID`, not `serverID`, because that's what the UI navigates with
    /// uniformly regardless of whether a session came from the server or (in standalone mode)
    /// was created purely locally.
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
}

public enum SessionSyncError: Error {
    case noDeviceToken
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
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

    @discardableResult
    private func upsert(_ dto: SessionDTO) -> UUID {
        let sessionServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == sessionServerID })
        )
        let primaryProtocolClientID = primaryProtocolClientID(forServerIDs: dto.protocols)
        let cachedSession = existing?.first ?? {
            let created = CachedSession(
                serverID: dto.id,
                uniqueID: dto.uniqueId,
                name: dto.name,
                enabled: dto.enabled,
                isRunning: dto.isRunning,
                status: dto.status,
                protocolServerIDs: dto.protocols,
                primaryProtocolClientID: primaryProtocolClientID
            )
            modelContext.insert(created)
            return created
        }()
        cachedSession.uniqueID = dto.uniqueId
        cachedSession.name = dto.name
        cachedSession.enabled = dto.enabled
        cachedSession.isRunning = dto.isRunning
        cachedSession.status = dto.status
        cachedSession.protocolServerIDs = dto.protocols
        if cachedSession.primaryProtocolClientID == nil {
            cachedSession.primaryProtocolClientID = primaryProtocolClientID
        }
        return cachedSession.clientID
    }

    /// Resolves the server's M2M `protocols: [Int64]` to the locally-cached protocol's
    /// `clientID`, so the UI can navigate session -> protocol the same way regardless of origin.
    private func primaryProtocolClientID(forServerIDs protocolServerIDs: [Int64]) -> UUID? {
        guard let firstProtocolServerID = protocolServerIDs.first else { return nil }
        let match = try? modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == firstProtocolServerID })
        )
        return match?.first?.clientID
    }
}
