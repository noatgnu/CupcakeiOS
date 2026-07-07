import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Full-refetch population of instruments and their booking history, plus `InstrumentUsage` offline-create.
public actor InstrumentSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: InstrumentStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = InstrumentStore(modelContainer: modelContainer)
    }

    public func refetchInstruments() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<InstrumentDTO> = try await apiClient.get("instruments/", authorizationHeader: authorization)
        while true {
            try await store.upsertInstruments(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    public func refetchInstrumentUsage() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<InstrumentUsageDTO> = try await apiClient.get("instrument-usage/", authorizationHeader: authorization)
        while true {
            try await store.upsertInstrumentUsage(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Pushes an already locally-created booking to the server, attaching the new `serverID`. Never sends `approved`.
    @discardableResult
    public func syncLocallyCreatedInstrumentUsage(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw InstrumentSyncError.noDeviceToken
        }
        let fields = try await store.instrumentUsageFields(clientID: clientID)
        let dto: InstrumentUsageDTO = try await apiClient.send(
            "instrument-usage/",
            method: .post,
            body: CreateInstrumentUsageRequest(
                instrument: fields.instrumentServerID,
                timeStarted: fields.timeStarted,
                timeEnded: fields.timeEnded,
                description: fields.description,
                maintenance: fields.maintenance
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(instrumentUsageClientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func createInstrument(instrumentName: String, instrumentDescription: String?, enabled: Bool, acceptsBookings: Bool, allowOverlappingBookings: Bool) async throws -> InstrumentDTO {
        guard let token = deviceToken() else {
            throw InstrumentSyncError.noDeviceToken
        }
        let dto: InstrumentDTO = try await apiClient.send(
            "instruments/",
            method: .post,
            body: CreateInstrumentRequest(
                instrumentName: instrumentName,
                instrumentDescription: instrumentDescription,
                enabled: enabled,
                acceptsBookings: acceptsBookings,
                allowOverlappingBookings: allowOverlappingBookings
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertInstruments([dto])
        return dto
    }

    @discardableResult
    public func updateInstrument(serverID: Int64, instrumentName: String, instrumentDescription: String?, enabled: Bool, acceptsBookings: Bool, allowOverlappingBookings: Bool) async throws -> InstrumentDTO {
        guard let token = deviceToken() else {
            throw InstrumentSyncError.noDeviceToken
        }
        let dto: InstrumentDTO = try await apiClient.send(
            "instruments/\(serverID)/",
            method: .patch,
            body: UpdateInstrumentRequest(
                instrumentName: instrumentName,
                instrumentDescription: instrumentDescription,
                enabled: enabled,
                acceptsBookings: acceptsBookings,
                allowOverlappingBookings: allowOverlappingBookings
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertInstruments([dto])
        return dto
    }

    public func deleteInstrument(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw InstrumentSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "instruments/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeInstrumentLocally(serverID: serverID)
    }
}

public enum InstrumentSyncError: Error {
    case noDeviceToken
    case instrumentUsageNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor InstrumentStore {
    func upsertInstruments(_ dtos: [InstrumentDTO]) throws {
        for dto in dtos {
            let instrumentID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedInstrument>(predicate: #Predicate { $0.serverID == instrumentID })
            )
            let instrument = existing?.first ?? {
                let created = CachedInstrument(
                    serverID: dto.id,
                    instrumentName: dto.instrumentName,
                    instrumentDescription: dto.instrumentDescription,
                    enabled: dto.enabled,
                    acceptsBookings: dto.acceptsBookings,
                    allowOverlappingBookings: dto.allowOverlappingBookings,
                    maintenanceOverdue: dto.maintenanceOverdue
                )
                modelContext.insert(created)
                return created
            }()
            instrument.instrumentName = dto.instrumentName
            instrument.instrumentDescription = dto.instrumentDescription
            instrument.enabled = dto.enabled
            instrument.acceptsBookings = dto.acceptsBookings
            instrument.allowOverlappingBookings = dto.allowOverlappingBookings
            instrument.maintenanceOverdue = dto.maintenanceOverdue
        }
        try modelContext.save()
    }

    func upsertInstrumentUsage(_ dtos: [InstrumentUsageDTO]) throws {
        for dto in dtos {
            let usageID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedInstrumentUsage>(predicate: #Predicate { $0.serverID == usageID })
            )
            let usage = existing?.first ?? {
                let created = CachedInstrumentUsage(
                    serverID: dto.id,
                    instrumentServerID: dto.instrument,
                    instrumentName: dto.instrumentName,
                    timeStarted: dto.timeStarted,
                    timeEnded: dto.timeEnded,
                    usageDescription: dto.description,
                    approved: dto.approved,
                    maintenance: dto.maintenance
                )
                modelContext.insert(created)
                return created
            }()
            usage.instrumentServerID = dto.instrument
            usage.instrumentName = dto.instrumentName
            usage.timeStarted = dto.timeStarted
            usage.timeEnded = dto.timeEnded
            usage.usageDescription = dto.description
            usage.approved = dto.approved
            usage.maintenance = dto.maintenance
        }
        try modelContext.save()
    }

    func removeInstrumentLocally(serverID: Int64) throws {
        guard let instrument = try modelContext.fetch(
            FetchDescriptor<CachedInstrument>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(instrument)
        try modelContext.save()
    }

    func instrumentUsageFields(clientID: UUID) throws -> (instrumentServerID: Int64, timeStarted: String, timeEnded: String?, description: String, maintenance: Bool) {
        guard let usage = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentUsage>(predicate: #Predicate { $0.clientID == clientID })
        ).first, let timeStarted = usage.timeStarted else {
            throw InstrumentSyncError.instrumentUsageNotCached
        }
        return (usage.instrumentServerID, timeStarted, usage.timeEnded, usage.usageDescription, usage.maintenance)
    }

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID`.
    func attachServerID(instrumentUsageClientID: UUID, dto: InstrumentUsageDTO) throws {
        guard let usage = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentUsage>(predicate: #Predicate { $0.clientID == instrumentUsageClientID })
        ).first else {
            throw InstrumentSyncError.instrumentUsageNotCached
        }
        usage.serverID = dto.id
        usage.timeStarted = dto.timeStarted
        usage.timeEnded = dto.timeEnded
        usage.usageDescription = dto.description
        usage.approved = dto.approved
        usage.maintenance = dto.maintenance
        try modelContext.save()
    }
}
