import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch, read-only population of instruments and their booking history.
/// Offline-create for `InstrumentUsage` (a booking request) is Phase 3.
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
}
