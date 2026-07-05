import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch, read-only population of server-side step-reagent recipe data —
/// completes the read side of the Protocol -> Section -> Step -> StepReagent hierarchy for
/// protocols fetched from the server. Local authoring of `StepReagent`s (attaching a reagent to
/// a step you're writing yourself, online or in standalone mode) is a separate, always-local
/// path — see `CachedStepReagent`'s doc comment — this service never creates one, only mirrors
/// what the server already has.
public actor StepReagentSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: StepReagentStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = StepReagentStore(modelContainer: modelContainer)
    }

    /// Run this after `ProtocolSyncService.refetchAll()` — resolving a step-reagent's `stepClientID`
    /// depends on its step already being cached.
    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<StepReagentDTO> = try await apiClient.get("step-reagents/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Same "sync the existing local record in place" shape as
    /// `ProtocolSyncService.syncLocallyCreatedProtocol` — the create-locally-then-sync path used
    /// when signed in, and what `OutboxService.replay(_:)` calls to retry a queued
    /// `createStepReagent` entry. Handles the reagent itself inline: if the attached reagent
    /// doesn't have a `serverID` yet (a brand-new reagent, or one only ever created locally
    /// before), it's created on the server first and its `serverID` attached, all within this
    /// one call — a step-reagent's reagent has no independent existence in this app's UI outside
    /// this attachment flow, so there's no separate `createReagent` outbox entry type to manage.
    ///
    /// Throws `SyncDependencyError.parentNotSynced` if the step itself hasn't synced yet — an
    /// ordering issue, retried like a connectivity failure, not a terminal error.
    @discardableResult
    public func syncLocallyCreatedStepReagent(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StepReagentSyncError.noDeviceToken
        }
        let fields = try await store.stepReagentFields(clientID: clientID)
        guard let stepServerID = fields.stepServerID else {
            throw SyncDependencyError.parentNotSynced
        }

        let reagentServerID: Int64
        if let existingReagentServerID = fields.reagentServerID {
            reagentServerID = existingReagentServerID
        } else {
            let reagentDTO: ReagentDTO = try await apiClient.send(
                "reagents/",
                method: .post,
                body: CreateReagentRequest(name: fields.reagentName, unit: fields.reagentUnit),
                authorizationHeader: "DeviceToken \(token)"
            )
            try await store.attachReagentServerID(reagentClientID: fields.reagentClientID, dto: reagentDTO)
            reagentServerID = reagentDTO.id
        }

        let dto: StepReagentDTO = try await apiClient.send(
            "step-reagents/",
            method: .post,
            body: CreateStepReagentRequest(step: stepServerID, reagentId: reagentServerID, quantity: fields.quantity, scalable: fields.scalable, scalableFactor: fields.scalableFactor),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(stepReagentClientID: clientID, dto: dto)
        return dto.id
    }
}

public enum StepReagentSyncError: Error {
    case noDeviceToken
    case stepReagentNotCached
    case reagentNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor StepReagentStore {
    func upsert(_ dtos: [StepReagentDTO]) throws {
        for dto in dtos {
            upsert(dto)
        }
        try modelContext.save()
    }

    private func upsert(_ dto: StepReagentDTO) {
        // A step-reagent whose step isn't cached yet (not owned/visible to this device, or not
        // synced yet this cycle) can't be resolved to a local clientID — skip it, same pattern
        // as SessionAnnotationStore's unresolved-session case; it'll resolve once the step syncs.
        let stepServerID = dto.step
        guard let step = try? modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == stepServerID })
        ).first else { return }

        let reagentClientID = upsertReagent(dto.reagent)

        let stepReagentServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == stepReagentServerID })
        )
        let stepReagent = existing?.first ?? {
            let created = CachedStepReagent(
                serverID: dto.id,
                stepClientID: step.clientID,
                reagentClientID: reagentClientID,
                quantity: dto.quantity,
                scalable: dto.scalable,
                scalableFactor: dto.scalableFactor
            )
            modelContext.insert(created)
            return created
        }()
        stepReagent.stepClientID = step.clientID
        stepReagent.reagentClientID = reagentClientID
        stepReagent.quantity = dto.quantity
        stepReagent.scalable = dto.scalable
        stepReagent.scalableFactor = dto.scalableFactor
    }

    func stepReagentFields(clientID: UUID) throws -> (
        stepServerID: Int64?,
        reagentClientID: UUID,
        reagentServerID: Int64?,
        reagentName: String,
        reagentUnit: String,
        quantity: Double,
        scalable: Bool,
        scalableFactor: Double
    ) {
        guard let stepReagent = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepReagentSyncError.stepReagentNotCached
        }
        let stepClientID = stepReagent.stepClientID
        let step = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first

        let reagentClientID = stepReagent.reagentClientID
        guard let reagent = try modelContext.fetch(
            FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.clientID == reagentClientID })
        ).first else {
            throw StepReagentSyncError.reagentNotCached
        }

        return (
            step?.serverID,
            reagentClientID,
            reagent.serverID,
            reagent.name,
            reagent.unit,
            stepReagent.quantity,
            stepReagent.scalable,
            stepReagent.scalableFactor
        )
    }

    /// Attaches a newly-assigned `serverID` to the existing local reagent matched by `clientID`.
    func attachReagentServerID(reagentClientID: UUID, dto: ReagentDTO) throws {
        guard let reagent = try modelContext.fetch(
            FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.clientID == reagentClientID })
        ).first else {
            throw StepReagentSyncError.reagentNotCached
        }
        reagent.serverID = dto.id
        reagent.name = dto.name
        reagent.unit = dto.unit
        try modelContext.save()
    }

    /// Attaches a newly-assigned `serverID` to the existing local step-reagent matched by
    /// `clientID` — the record already exists (created locally first), so this updates it in
    /// place rather than inserting a second copy.
    func attachServerID(stepReagentClientID: UUID, dto: StepReagentDTO) throws {
        guard let stepReagent = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.clientID == stepReagentClientID })
        ).first else {
            throw StepReagentSyncError.stepReagentNotCached
        }
        stepReagent.serverID = dto.id
        stepReagent.quantity = dto.quantity
        stepReagent.scalable = dto.scalable
        stepReagent.scalableFactor = dto.scalableFactor
        try modelContext.save()
    }

    private func upsertReagent(_ dto: ReagentDTO) -> UUID {
        let reagentServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.serverID == reagentServerID })
        )
        let reagent = existing?.first ?? {
            let created = CachedReagent(serverID: dto.id, name: dto.name, unit: dto.unit)
            modelContext.insert(created)
            return created
        }()
        reagent.name = dto.name
        reagent.unit = dto.unit
        return reagent.clientID
    }
}
