import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch population only (no `updated_at__gte` delta cursor yet — that lands in
/// Phase 2 alongside the outbox). Protocols/sections/steps are read-only reference data, so this
/// service only ever upserts; it never has to reconcile a locally-created record.
public actor ProtocolSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: ProtocolStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = ProtocolStore(modelContainer: modelContainer)
    }

    /// Fetches every protocol the user can see and upserts it (and its sections/steps) into
    /// the local store. Silently does nothing if there's no stored `DeviceToken` yet.
    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<ProtocolDTO> = try await apiClient.get("protocols/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Pushes an *already locally-created* protocol to the server, attaching the new `serverID`
    /// to that same local record instead of creating a duplicate — the create-locally-then-sync
    /// path used when signed in (see `NewProtocolView`), and what `OutboxService.replay(_:)`
    /// calls to retry a queued `createProtocol` entry.
    @discardableResult
    public func syncLocallyCreatedProtocol(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let fields = try await store.protocolFields(clientID: clientID)
        let dto: ProtocolDTO = try await apiClient.send(
            "protocols/",
            method: .post,
            body: CreateProtocolRequest(protocolTitle: fields.title, protocolDescription: fields.description, enabled: fields.enabled),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }

    /// Same "sync the existing local record in place" shape as `syncLocallyCreatedProtocol`, for
    /// a section. If the parent protocol hasn't synced yet (queued in the outbox behind it, or
    /// simply hasn't been attempted yet), throws `SyncDependencyError.parentNotSynced` —
    /// `OutboxService` treats that the same as a connectivity failure (retry later), not a
    /// terminal error, since it's purely an ordering issue that resolves itself once the
    /// protocol's own entry replays.
    @discardableResult
    public func syncLocallyCreatedSection(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let fields = try await store.sectionFields(clientID: clientID)
        guard let protocolServerID = fields.protocolServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: ProtocolSectionDTO = try await apiClient.send(
            "sections/",
            method: .post,
            body: CreateProtocolSectionRequest(protocolServerID: protocolServerID, sectionDescription: fields.description, sectionDuration: fields.duration, order: fields.order),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(sectionClientID: clientID, dto: dto)
        return dto.id
    }

    /// Same shape again, for a step — needs both its parent protocol's and its own section's
    /// `serverID`, either of which might not exist yet if they're still queued ahead of it.
    @discardableResult
    public func syncLocallyCreatedStep(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let fields = try await store.stepFields(clientID: clientID)
        guard let protocolServerID = fields.protocolServerID, let sectionServerID = fields.sectionServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: ProtocolStepDTO = try await apiClient.send(
            "steps/",
            method: .post,
            body: CreateProtocolStepRequest(protocolServerID: protocolServerID, sectionServerID: sectionServerID, stepDescription: fields.description, stepDuration: fields.duration, order: fields.order),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(stepClientID: clientID, dto: dto)
        return dto.id
    }
}

public enum ProtocolSyncError: Error {
    case noDeviceToken
    case protocolNotCached
    case sectionNotCached
    case stepNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — the `@ModelActor` macro synthesizes its
/// own initializer that only knows about `modelContainer`, so it can't hold extra stored
/// properties like `APIClient` alongside it. `ProtocolSyncService` owns the network/orchestration
/// side; this owns persistence only.
@ModelActor
actor ProtocolStore {
    func upsert(_ dtos: [ProtocolDTO]) throws {
        for dto in dtos {
            upsert(dto)
        }
        try modelContext.save()
    }

    func protocolFields(clientID: UUID) throws -> (title: String, description: String?, enabled: Bool) {
        guard let cachedProtocol = try modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProtocolSyncError.protocolNotCached
        }
        return (cachedProtocol.protocolTitle, cachedProtocol.protocolDescription, cachedProtocol.enabled)
    }

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID` —
    /// the record already exists (created locally first), so this updates it in place rather
    /// than inserting a second copy the way the read-sync `upsert` methods do.
    func attachServerID(clientID: UUID, dto: ProtocolDTO) throws {
        guard let cachedProtocol = try modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProtocolSyncError.protocolNotCached
        }
        cachedProtocol.serverID = dto.id
        cachedProtocol.isLocallyAuthored = true
        cachedProtocol.protocolTitle = dto.protocolTitle
        cachedProtocol.protocolDescription = dto.protocolDescription
        cachedProtocol.enabled = dto.enabled
        try modelContext.save()
    }

    func sectionFields(clientID: UUID) throws -> (protocolServerID: Int64?, description: String?, duration: Int?, order: Int) {
        guard let section = try modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProtocolSyncError.sectionNotCached
        }
        return (section.protocolModel?.serverID, section.sectionDescription, section.sectionDuration, section.order)
    }

    func stepFields(clientID: UUID) throws -> (protocolServerID: Int64?, sectionServerID: Int64?, description: String, duration: Int?, order: Int) {
        guard let step = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProtocolSyncError.stepNotCached
        }
        return (step.section?.protocolModel?.serverID, step.section?.serverID, step.stepDescription, step.stepDuration, step.order)
    }

    /// Attaches a newly-assigned `serverID` to the existing local section matched by `clientID`.
    func attachServerID(sectionClientID: UUID, dto: ProtocolSectionDTO) throws {
        guard let section = try modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.clientID == sectionClientID })
        ).first else {
            throw ProtocolSyncError.sectionNotCached
        }
        section.serverID = dto.id
        section.sectionDescription = dto.sectionDescription
        section.sectionDuration = dto.sectionDuration
        section.order = dto.order
        try modelContext.save()
    }

    /// Attaches a newly-assigned `serverID` to the existing local step matched by `clientID`.
    func attachServerID(stepClientID: UUID, dto: ProtocolStepDTO) throws {
        guard let step = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first else {
            throw ProtocolSyncError.stepNotCached
        }
        step.serverID = dto.id
        step.stepDescription = dto.stepDescription
        step.stepDuration = dto.stepDuration
        step.order = dto.order
        try modelContext.save()
    }

    private func upsert(_ dto: ProtocolDTO) {
        let protocolServerID = dto.id
        let existingProtocols = try? modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == protocolServerID })
        )
        let cachedProtocol = existingProtocols?.first ?? {
            let created = CachedProtocol(
                serverID: dto.id,
                protocolTitle: dto.protocolTitle,
                protocolDescription: dto.protocolDescription,
                enabled: dto.enabled
            )
            modelContext.insert(created)
            return created
        }()
        cachedProtocol.protocolTitle = dto.protocolTitle
        cachedProtocol.protocolDescription = dto.protocolDescription
        cachedProtocol.enabled = dto.enabled

        for sectionDTO in dto.sections {
            upsert(sectionDTO, into: cachedProtocol)
        }
    }

    private func upsert(_ dto: ProtocolSectionDTO, into cachedProtocol: CachedProtocol) {
        let sectionServerID = dto.id
        let existingSections = try? modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.serverID == sectionServerID })
        )
        let section = existingSections?.first ?? {
            let created = CachedProtocolSection(
                serverID: dto.id,
                sectionDescription: dto.sectionDescription,
                order: dto.order,
                sectionDuration: dto.sectionDuration,
                protocolModel: cachedProtocol
            )
            modelContext.insert(created)
            return created
        }()
        section.sectionDescription = dto.sectionDescription
        section.order = dto.order
        section.sectionDuration = dto.sectionDuration
        section.protocolModel = cachedProtocol

        for stepDTO in dto.steps {
            upsert(stepDTO, into: section)
        }
    }

    private func upsert(_ dto: ProtocolStepDTO, into section: CachedProtocolSection) {
        let stepServerID = dto.id
        let existingSteps = try? modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == stepServerID })
        )
        let step = existingSteps?.first ?? {
            let created = CachedProtocolStep(
                serverID: dto.id,
                stepDescription: dto.stepDescription,
                order: dto.order,
                stepDuration: dto.stepDuration,
                section: section
            )
            modelContext.insert(created)
            return created
        }()
        step.stepDescription = dto.stepDescription
        step.order = dto.order
        step.stepDuration = dto.stepDuration
        step.section = section
    }
}
