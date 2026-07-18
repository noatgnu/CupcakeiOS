import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

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

    @discardableResult
    public func update(serverID: Int64, quantity: Double, scalable: Bool, scalableFactor: Double) async throws -> StepReagentDTO {
        guard let token = deviceToken() else {
            throw StepReagentSyncError.noDeviceToken
        }
        let dto: StepReagentDTO = try await apiClient.send(
            "step-reagents/\(serverID)/",
            method: .patch,
            body: UpdateStepReagentRequest(quantity: quantity, scalable: scalable, scalableFactor: scalableFactor),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.updateLocally(serverID: serverID, dto: dto)
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw StepReagentSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "step-reagents/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(serverID: serverID)
    }
}

public enum StepReagentSyncError: Error {
    case noDeviceToken
    case stepReagentNotCached
    case reagentNotCached
}

@ModelActor
actor StepReagentStore {
    func upsert(_ dtos: [StepReagentDTO]) throws {
        for dto in dtos {
            upsert(dto)
        }
        try modelContext.save()
    }

    private func upsert(_ dto: StepReagentDTO) {
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

    func updateLocally(serverID: Int64, dto: StepReagentDTO) throws {
        guard let stepReagent = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        stepReagent.quantity = dto.quantity
        stepReagent.scalable = dto.scalable
        stepReagent.scalableFactor = dto.scalableFactor
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let stepReagent = try modelContext.fetch(
            FetchDescriptor<CachedStepReagent>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(stepReagent)
        try modelContext.save()
    }

    private func upsertReagent(_ dto: ReagentDTO) -> UUID {
        let reagentServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedReagent>(predicate: #Predicate { $0.serverID == reagentServerID })
        )
        let reagent = existing?.first ?? {
            let created = CachedReagent(serverID: dto.id, name: dto.name, unit: dto.unit, createdAt: Date.parsedISO8601(dto.createdAt))
            modelContext.insert(created)
            return created
        }()
        reagent.name = dto.name
        reagent.unit = dto.unit
        reagent.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: reagent.updatedAt)
        return reagent.clientID
    }
}
