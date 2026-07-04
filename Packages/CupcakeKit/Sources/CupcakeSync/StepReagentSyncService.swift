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

    /// Creates a brand-new server-side `Reagent` — only needed when attaching a reagent that
    /// doesn't already exist there (an existing reagent is referenced by its own `serverID`
    /// instead). Returns `(clientID, serverID)` so the caller can immediately use the `serverID`
    /// in a follow-up `createStepReagent` call without a second round-trip.
    public func createReagent(name: String, unit: String) async throws -> (clientID: UUID, serverID: Int64) {
        guard let token = deviceToken() else {
            throw StepReagentSyncError.noDeviceToken
        }
        let dto: ReagentDTO = try await apiClient.send(
            "reagents/",
            method: .post,
            body: CreateReagentRequest(name: name, unit: unit),
            authorizationHeader: "DeviceToken \(token)"
        )
        let clientID = try await store.upsertSingle(dto)
        return (clientID, dto.id)
    }

    @discardableResult
    public func createStepReagent(stepServerID: Int64, reagentServerID: Int64, quantity: Double, scalable: Bool, scalableFactor: Double) async throws -> UUID {
        guard let token = deviceToken() else {
            throw StepReagentSyncError.noDeviceToken
        }
        let dto: StepReagentDTO = try await apiClient.send(
            "step-reagents/",
            method: .post,
            body: CreateStepReagentRequest(step: stepServerID, reagentId: reagentServerID, quantity: quantity, scalable: scalable, scalableFactor: scalableFactor),
            authorizationHeader: "DeviceToken \(token)"
        )
        return try await store.upsertSingle(dto)
    }
}

public enum StepReagentSyncError: Error {
    case noDeviceToken
    case stepNotCached
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

    func upsertSingle(_ dto: ReagentDTO) throws -> UUID {
        let clientID = upsertReagent(dto)
        try modelContext.save()
        return clientID
    }

    func upsertSingle(_ dto: StepReagentDTO) throws -> UUID {
        upsert(dto)
        try modelContext.save()
        let stepReagentServerID = dto.id
        guard let stepReagent = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == stepReagentServerID })
        ).first else {
            throw StepReagentSyncError.stepNotCached
        }
        return stepReagent.clientID
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
