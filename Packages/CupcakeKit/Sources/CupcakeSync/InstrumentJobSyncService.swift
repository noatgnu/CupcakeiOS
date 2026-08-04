import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

public actor InstrumentJobSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: InstrumentJobStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = InstrumentJobStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        try await apiClient.fetchAllPages(path: "instrument-jobs/", authorizationHeader: "DeviceToken \(token)") { (dtos: [InstrumentJobDTO]) in
            try await store.upsert(dtos)
        }
    }

    @discardableResult
    public func syncLocallyCreatedInstrumentJob(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let fields = try await store.instrumentJobFields(clientID: clientID)
        let projectServerID: Int64?
        if fields.projectClientID != nil {
            guard let resolvedProjectServerID = fields.projectServerID else {
                throw SyncDependencyError.parentNotSynced
            }
            projectServerID = resolvedProjectServerID
        } else {
            projectServerID = nil
        }

        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/",
            method: .post,
            body: CreateInstrumentJobRequest(jobType: fields.jobType, jobName: fields.jobName, project: projectServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }

    @discardableResult
    public func submit(jobServerID: Int64) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/submit/",
            method: .post,
            body: EmptyEncodable(),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    @discardableResult
    public func cancel(jobServerID: Int64) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/cancel/",
            method: .post,
            body: EmptyEncodable(),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    @discardableResult
    public func createMetadataFromTemplate(
        jobServerID: Int64,
        jobClientID: UUID,
        templateID: Int64,
        sampleCount: Int? = nil,
        labGroupID: Int64? = nil
    ) async throws -> MetadataTableDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"
        let response: CreateMetadataFromTemplateResponse = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/create_metadata_from_template/",
            method: .post,
            body: CreateMetadataFromTemplateRequest(templateId: templateID, sampleCount: sampleCount, labGroupId: labGroupID),
            authorizationHeader: authorization
        )
        try await store.upsertMetadataTable(response.metadataTable, instrumentJobClientID: jobClientID)

        let updatedJob: InstrumentJobDTO = try await apiClient.get("instrument-jobs/\(jobServerID)/", authorizationHeader: authorization)
        try await store.upsertSingle(updatedJob)

        return response.metadataTable
    }

    @discardableResult
    public func updateLabGroup(jobServerID: Int64, labGroupServerID: Int64) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/",
            method: .patch,
            body: UpdateInstrumentJobLabGroupRequest(labGroup: labGroupServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    @discardableResult
    public func updateInstrument(jobServerID: Int64, instrumentServerID: Int64) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/",
            method: .patch,
            body: UpdateInstrumentJobInstrumentRequest(instrument: instrumentServerID),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    @discardableResult
    public func updateStaff(jobServerID: Int64, staffServerIDs: [Int64]) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/",
            method: .patch,
            body: UpdateInstrumentJobStaffRequest(staff: staffServerIDs),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    @discardableResult
    public func refreshMetadataTable(jobServerID: Int64, jobClientID: UUID) async throws -> MetadataTableDTO? {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"
        let updatedJob: InstrumentJobDTO = try await apiClient.get("instrument-jobs/\(jobServerID)/", authorizationHeader: authorization)
        try await store.upsertSingle(updatedJob)

        guard let metadataTableServerID = updatedJob.metadataTable else { return nil }
        let table: MetadataTableDTO = try await apiClient.get("metadata-tables/\(metadataTableServerID)/", authorizationHeader: authorization)
        try await store.upsertMetadataTable(table, instrumentJobClientID: jobClientID)
        return table
    }

    @discardableResult
    public func updateFunderCostCenter(jobServerID: Int64, funder: String?, costCenter: String?) async throws -> InstrumentJobDTO {
        guard let token = deviceToken() else {
            throw InstrumentJobSyncError.noDeviceToken
        }
        let dto: InstrumentJobDTO = try await apiClient.send(
            "instrument-jobs/\(jobServerID)/",
            method: .patch,
            body: UpdateInstrumentJobFunderCostCenterRequest(funder: funder, costCenter: costCenter),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.upsertSingle(dto)
        return dto
    }

    public func fetchProjectColumnValues(projectServerID: Int64, columnName: String) async throws -> [String] {
        guard let token = deviceToken() else { return [] }
        let response: ProjectColumnValuesResponse = try await apiClient.get(
            "instrument-jobs/project_column_values/",
            query: [
                URLQueryItem(name: "project_id", value: String(projectServerID)),
                URLQueryItem(name: "column_name", value: columnName),
            ],
            authorizationHeader: "DeviceToken \(token)"
        )
        return response.values
    }
}

private struct EmptyEncodable: Encodable, Sendable {}

public enum InstrumentJobSyncError: Error {
    case noDeviceToken
    case instrumentJobNotCached
}

@ModelActor
actor InstrumentJobStore {
    func upsert(_ dtos: [InstrumentJobDTO]) throws {
        for dto in dtos {
            upsert(dto)
        }
        try modelContext.save()
    }

    func upsertSingle(_ dto: InstrumentJobDTO) throws {
        upsert(dto)
        try modelContext.save()
    }

    private func upsert(_ dto: InstrumentJobDTO) {
        let jobServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedInstrumentJob>(predicate: #Predicate { $0.serverID == jobServerID })
        )
        let projectClientID = resolveProjectClientID(forServerID: dto.project)
        let job = existing?.first ?? {
            let created = CachedInstrumentJob(
                serverID: dto.id,
                jobName: dto.jobName,
                jobType: dto.jobType,
                status: dto.status,
                projectClientID: projectClientID,
                instrumentServerID: dto.instrument,
                submittedAt: dto.submittedAt,
                completedAt: dto.completedAt,
                metadataTableServerID: dto.metadataTable,
                labGroupServerID: dto.labGroup,
                staffServerIDs: dto.staff,
                staffUsernames: dto.staffUsernames,
                canEditStaffOnlyColumns: dto.canEditStaffOnlyColumns,
                funder: dto.funder,
                costCenter: dto.costCenter,
                createdAt: Date.parsedISO8601(dto.createdAt),
                ownerServerID: dto.user,
                ownerUsername: dto.userUsername
            )
            modelContext.insert(created)
            return created
        }()
        job.jobName = dto.jobName
        job.jobType = dto.jobType
        job.status = dto.status
        if job.projectClientID == nil { job.projectClientID = projectClientID }
        job.instrumentServerID = dto.instrument
        job.submittedAt = dto.submittedAt
        job.completedAt = dto.completedAt
        job.metadataTableServerID = dto.metadataTable
        job.labGroupServerID = dto.labGroup
        job.staffServerIDs = dto.staff
        job.staffUsernames = dto.staffUsernames
        job.canEditStaffOnlyColumns = dto.canEditStaffOnlyColumns
        job.funder = dto.funder
        job.costCenter = dto.costCenter
        job.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: job.updatedAt)
        job.ownerServerID = dto.user
        job.ownerUsername = dto.userUsername
    }

    func upsertMetadataTable(_ dto: MetadataTableDTO, instrumentJobClientID: UUID) throws {
        let tableServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedMetadataTable>(predicate: #Predicate { $0.serverID == tableServerID })
        )
        let table = existing?.first ?? {
            let created = CachedMetadataTable(serverID: dto.id, name: dto.name, instrumentJobClientID: instrumentJobClientID)
            modelContext.insert(created)
            return created
        }()
        table.name = dto.name
        table.tableDescription = dto.description
        table.sampleCount = dto.sampleCount
        table.version = dto.version
        table.ownerUsername = dto.ownerUsername
        table.labGroupName = dto.labGroupName
        table.isPublished = dto.isPublished
        table.canEdit = dto.canEdit
        table.instrumentJobClientID = instrumentJobClientID

        let existingColumns = try? modelContext.fetch(
            FetchDescriptor<CachedMetadataColumn>(predicate: #Predicate { $0.metadataTableServerID == tableServerID })
        )
        for column in existingColumns ?? [] {
            modelContext.delete(column)
        }
        for columnDTO in dto.columns {
            let column = CachedMetadataColumn(
                serverID: columnDTO.id,
                metadataTableServerID: dto.id,
                name: columnDTO.name,
                displayName: columnDTO.displayName,
                type: columnDTO.type,
                columnPosition: columnDTO.columnPosition ?? 0,
                value: columnDTO.value,
                notApplicable: columnDTO.notApplicable,
                notAvailable: columnDTO.notAvailable,
                mandatory: columnDTO.mandatory,
                hidden: columnDTO.hidden,
                readonly: columnDTO.readonly,
                ontologyType: columnDTO.ontologyType,
                staffOnly: columnDTO.staffOnly,
                modifiers: columnDTO.modifiers.map { MetadataColumnModifier(samples: $0.samples, value: $0.value) }
            )
            modelContext.insert(column)
        }
        try modelContext.save()
    }

    private func resolveProjectClientID(forServerID projectServerID: Int64?) -> UUID? {
        guard let projectServerID else { return nil }
        let match = try? modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == projectServerID })
        )
        return match?.first?.clientID
    }

    func instrumentJobFields(clientID: UUID) throws -> (jobName: String?, jobType: String, projectClientID: UUID?, projectServerID: Int64?) {
        guard let job = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentJob>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw InstrumentJobSyncError.instrumentJobNotCached
        }
        var projectServerID: Int64?
        if let projectClientID = job.projectClientID {
            let match = try? modelContext.fetch(
                FetchDescriptor<CachedProject>(predicate: #Predicate { $0.clientID == projectClientID })
            )
            projectServerID = match?.first?.serverID
        }
        return (job.jobName, job.jobType, job.projectClientID, projectServerID)
    }

    func attachServerID(clientID: UUID, dto: InstrumentJobDTO) throws {
        guard let job = try modelContext.fetch(
            FetchDescriptor<CachedInstrumentJob>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw InstrumentJobSyncError.instrumentJobNotCached
        }
        job.serverID = dto.id
        job.jobName = dto.jobName
        job.jobType = dto.jobType
        job.status = dto.status
        job.instrumentServerID = dto.instrument
        job.submittedAt = dto.submittedAt
        job.completedAt = dto.completedAt
        job.metadataTableServerID = dto.metadataTable
        job.labGroupServerID = dto.labGroup
        job.funder = dto.funder
        job.costCenter = dto.costCenter
        job.updatedAt = Date.parsedISO8601(dto.updatedAt, fallback: job.updatedAt)
        job.ownerServerID = dto.user
        job.ownerUsername = dto.userUsername
        try modelContext.save()
    }
}
