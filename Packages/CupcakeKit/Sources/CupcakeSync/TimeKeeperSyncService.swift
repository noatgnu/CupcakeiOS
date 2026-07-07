import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Per-session/step countdown timers. Online-only, get-or-create per session+step.
public actor TimeKeeperSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: TimeKeeperStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = TimeKeeperStore(modelContainer: modelContainer)
    }

    public func refetch(sessionServerID: Int64) async throws {
        try await store.upsert(fetchTimeKeepers(sessionServerID: sessionServerID), sessionClientID: store.sessionClientID(serverID: sessionServerID))
    }

    /// A pure network fetch with no cache write, for callers applying the result onto their own `ModelContext`.
    public func fetchTimeKeepers(sessionServerID: Int64) async throws -> [TimeKeeperDTO] {
        guard let token = deviceToken() else { return [] }
        let page: PaginatedResponse<TimeKeeperDTO> = try await apiClient.get(
            "time-keepers/",
            query: [URLQueryItem(name: "session", value: String(sessionServerID))],
            authorizationHeader: "DeviceToken \(token)"
        )
        return page.results
    }

    /// Creates, or reuses an existing match for, the timer for a session+step combination.
    @discardableResult
    public func create(sessionServerID: Int64, sessionClientID: UUID, stepServerID: Int64?, stepClientID: UUID?, durationSeconds: Int) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw TimeKeeperSyncError.noDeviceToken
        }
        let dto: TimeKeeperDTO = try await apiClient.send(
            "time-keepers/",
            method: .post,
            body: CreateTimeKeeperRequest(session: sessionServerID, step: stepServerID, currentDuration: durationSeconds, originalDuration: durationSeconds),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto, sessionClientID: sessionClientID, stepClientID: stepClientID)
        return dto.id
    }

    @discardableResult
    public func startTimer(serverID: Int64) async throws -> TimeKeeperDTO {
        try await performAction(serverID: serverID, action: "start_timer")
    }

    @discardableResult
    public func stopTimer(serverID: Int64) async throws -> TimeKeeperDTO {
        try await performAction(serverID: serverID, action: "stop_timer")
    }

    @discardableResult
    public func resetTimer(serverID: Int64) async throws -> TimeKeeperDTO {
        try await performAction(serverID: serverID, action: "reset")
    }

    private func performAction(serverID: Int64, action: String) async throws -> TimeKeeperDTO {
        guard let token = deviceToken() else {
            throw TimeKeeperSyncError.noDeviceToken
        }
        let response: TimeKeeperActionResponse = try await apiClient.send(
            "time-keepers/\(serverID)/\(action)/",
            method: .post,
            body: EmptyEncodable(),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(response.timeKeeper, sessionClientID: store.sessionClientID(serverID: response.timeKeeper.session), stepClientID: nil)
        return response.timeKeeper
    }
}

public enum TimeKeeperSyncError: Error {
    case noDeviceToken
}

private struct EmptyEncodable: Encodable, Sendable {}

actor TimeKeeperStore {
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContext = ModelContext(modelContainer)
    }

    func sessionClientID(serverID: Int64) throws -> UUID? {
        try modelContext.fetch(FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == serverID })).first?.clientID
    }

    func upsert(_ dtos: [TimeKeeperDTO], sessionClientID: UUID?) throws {
        for dto in dtos {
            try upsertSingle(dto, sessionClientID: sessionClientID, stepClientID: try stepClientID(serverID: dto.step))
        }
    }

    func upsertSingle(_ dto: TimeKeeperDTO, sessionClientID: UUID?, stepClientID: UUID?) throws {
        guard let sessionClientID else { return }
        let serverID = dto.id
        if let existing = try modelContext.fetch(FetchDescriptor<CachedTimeKeeper>(predicate: #Predicate { $0.serverID == serverID })).first {
            existing.started = dto.started
            existing.startTime = dto.startTime
            existing.currentDuration = dto.currentDuration
            existing.originalDuration = dto.originalDuration
        } else {
            modelContext.insert(CachedTimeKeeper(
                serverID: dto.id,
                sessionClientID: sessionClientID,
                stepClientID: stepClientID,
                started: dto.started,
                startTime: dto.startTime,
                currentDuration: dto.currentDuration,
                originalDuration: dto.originalDuration
            ))
        }
        try modelContext.save()
    }

    private func stepClientID(serverID: Int64?) throws -> UUID? {
        guard let serverID else { return nil }
        return try modelContext.fetch(FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == serverID })).first?.clientID
    }
}
