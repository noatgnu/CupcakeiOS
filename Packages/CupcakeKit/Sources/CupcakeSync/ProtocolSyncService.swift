import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

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

    public func fetchProtocolIDs(filter: ProtocolListFilter) async throws -> [Int64] {
        guard let token = deviceToken() else { return [] }
        let dtos: [ProtocolDTO] = try await apiClient.get("protocols/\(filter.rawValue)/", authorizationHeader: "DeviceToken \(token)")
        return dtos.map(\.id)
    }

    @discardableResult
    public func importFromProtocolsIO(url: String) async throws -> UUID {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let dto: ProtocolDTO = try await apiClient.send(
            "protocols/import_from_protocols_io/",
            method: .post,
            body: ImportProtocolFromURLRequest(url: url),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        guard let clientID = try await store.clientID(serverID: dto.id) else {
            throw ProtocolSyncError.importFailed
        }
        return clientID
    }

    public func fetchExportURL(protocolServerID: Int64, sessionServerID: Int64?) async throws -> URL {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        var query: [URLQueryItem] = []
        if let sessionServerID {
            query.append(URLQueryItem(name: "session", value: String(sessionServerID)))
        }
        let response: ExportURLResponse = try await apiClient.get(
            "protocols/\(protocolServerID)/get_export_url/",
            query: query,
            authorizationHeader: "DeviceToken \(token)"
        )
        guard let url = URL(string: response.downloadUrl) else {
            throw ProtocolSyncError.importFailed
        }
        return url
    }

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

    @discardableResult
    public func syncLocallyCreatedSection(clientID: UUID, knownProtocolServerID: Int64? = nil) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let fields = try await store.sectionFields(clientID: clientID)
        guard let protocolServerID = knownProtocolServerID ?? fields.protocolServerID else {
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

    @discardableResult
    public func syncLocallyCreatedStep(clientID: UUID, knownSectionServerID: Int64? = nil, knownProtocolServerID: Int64? = nil) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let fields = try await store.stepFields(clientID: clientID)
        guard let protocolServerID = knownProtocolServerID ?? fields.protocolServerID,
              let sectionServerID = knownSectionServerID ?? fields.sectionServerID else {
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

    @discardableResult
    public func update(serverID: Int64, protocolTitle: String, protocolDescription: String?, enabled: Bool) async throws -> ProtocolDTO {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let dto: ProtocolDTO = try await apiClient.send(
            "protocols/\(serverID)/",
            method: .patch,
            body: UpdateProtocolRequest(protocolTitle: protocolTitle, protocolDescription: protocolDescription, enabled: enabled),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsert([dto])
        return dto
    }

    public func delete(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "protocols/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeLocal(serverID: serverID)
    }

    @discardableResult
    public func updateSection(serverID: Int64, sectionDescription: String?, sectionDuration: Int?) async throws -> ProtocolSectionDTO {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let dto: ProtocolSectionDTO = try await apiClient.send(
            "sections/\(serverID)/",
            method: .patch,
            body: UpdateProtocolSectionRequest(sectionDescription: sectionDescription, sectionDuration: sectionDuration),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.updateSectionLocally(serverID: serverID, dto: dto)
        return dto
    }

    public func deleteSection(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "sections/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeSectionLocally(serverID: serverID)
    }

    @discardableResult
    public func updateStep(serverID: Int64, stepDescription: String, stepDuration: Int?) async throws -> ProtocolStepDTO {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        let dto: ProtocolStepDTO = try await apiClient.send(
            "steps/\(serverID)/",
            method: .patch,
            body: UpdateProtocolStepRequest(stepDescription: stepDescription, stepDuration: stepDuration),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.updateStepLocally(serverID: serverID, dto: dto)
        return dto
    }

    public func deleteStep(serverID: Int64) async throws {
        guard let token = deviceToken() else {
            throw ProtocolSyncError.noDeviceToken
        }
        try await apiClient.sendNoContent(
            "steps/\(serverID)/",
            method: .delete,
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.removeStepLocally(serverID: serverID)
    }
}

public enum ProtocolSyncError: Error {
    case noDeviceToken
    case protocolNotCached
    case sectionNotCached
    case stepNotCached
    case importFailed
}

public enum ProtocolListFilter: String, Sendable {
    case myProtocols = "my_protocols"
    case sharedWithMe = "shared_with_me"
    case publicProtocols = "public_protocols"
    case vaultedProtocols = "vaulted_protocols"
}

@ModelActor
actor ProtocolStore {
    func upsert(_ dtos: [ProtocolDTO]) throws {
        for dto in dtos {
            upsert(dto)
        }
        try modelContext.save()
    }

    func clientID(serverID: Int64) throws -> UUID? {
        try modelContext.fetch(FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == serverID })).first?.clientID
    }

    func protocolFields(clientID: UUID) throws -> (title: String, description: String?, enabled: Bool) {
        guard let cachedProtocol = try modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProtocolSyncError.protocolNotCached
        }
        return (cachedProtocol.protocolTitle, cachedProtocol.protocolDescription, cachedProtocol.enabled)
    }

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
        cachedProtocol.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: cachedProtocol.updatedAt)
        try modelContext.save()
    }

    func removeLocal(serverID: Int64) throws {
        guard let cachedProtocol = try modelContext.fetch(
            FetchDescriptor<CachedProtocol>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(cachedProtocol)
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

    func updateSectionLocally(serverID: Int64, dto: ProtocolSectionDTO) throws {
        guard let section = try modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        section.sectionDescription = dto.sectionDescription
        section.sectionDuration = dto.sectionDuration
        try modelContext.save()
    }

    func removeSectionLocally(serverID: Int64) throws {
        guard let section = try modelContext.fetch(
            FetchDescriptor<CachedProtocolSection>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(section)
        try modelContext.save()
    }

    func updateStepLocally(serverID: Int64, dto: ProtocolStepDTO) throws {
        guard let step = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        step.stepDescription = dto.stepDescription
        step.stepDuration = dto.stepDuration
        try modelContext.save()
    }

    func removeStepLocally(serverID: Int64) throws {
        guard let step = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.serverID == serverID })
        ).first else { return }
        modelContext.delete(step)
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
                enabled: dto.enabled,
                createdAt: Date.parsedISO8601(dto.createdAt)
            )
            modelContext.insert(created)
            return created
        }()
        cachedProtocol.protocolTitle = dto.protocolTitle
        cachedProtocol.protocolDescription = dto.protocolDescription
        cachedProtocol.enabled = dto.enabled
        cachedProtocol.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: cachedProtocol.updatedAt)

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
