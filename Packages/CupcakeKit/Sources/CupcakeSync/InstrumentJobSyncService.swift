import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Read-sync + create-locally-then-sync-or-queue + `submit`/`cancel` actions for
/// `InstrumentJob` — part of the independent Job subsystem (Phase 4.5). Deferred to a later
/// slice: lab group/staff assignment, `metadata_table_template`/`create_metadata_from_template`,
/// `InstrumentJobAnnotation`/`InstrumentUsageJobAnnotation` + the booking-merge flow.
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
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<InstrumentJobDTO> = try await apiClient.get("instrument-jobs/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Pushes an *already locally-created* job to the server, attaching the new `serverID` to
    /// that same local record. Throws `SyncDependencyError.parentNotSynced` if the job has a
    /// project that hasn't synced yet (an ordering issue, retried like a connectivity failure —
    /// same reasoning as every other parent-dependency case in this app). A job with no project
    /// at all (`projectClientID == nil`) has nothing to wait on and syncs immediately.
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

    /// Creates the job's `MetadataTable` from a template — the job must not already have one
    /// (`ccm/viewsets.py:588-669`). The response doesn't include the updated `InstrumentJob`
    /// itself, so this does a follow-up `GET` to pick up the new `metadata_table` link.
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

    /// Required before booking an instrument for a job — see `UpdateInstrumentJobInstrumentRequest`'s
    /// doc comment for why this exists at all.
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

    /// Replaces the job's entire staff list. Requires the job to already have a `lab_group` set
    /// (server-side validation rule 1) and every listed user to be a direct member of that lab
    /// group with `can_process_jobs` (rules 2-3) — see `UpdateInstrumentJobStaffRequest`'s doc
    /// comment. A rejection here is a real validation failure worth surfacing verbatim, not a
    /// generic "couldn't sync" — callers should inspect `APIError.http`'s body on failure.
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

    /// Re-fetches the job and its `metadata_table` — the metadata-merge signal
    /// (`ccm/signals.py:175-260`) runs synchronously inside the booking-annotation create
    /// request, so by the time that call returns, this pulls in whatever columns it merged.
    /// Returns `nil` if the job still has no `metadata_table` (nothing to refresh).
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
}

/// `submit`/`cancel` are DRF `@action`s that take no request body — `send(_:method:body:...)`
/// still needs *something* `Encodable` to serialize, so this is an explicit "no fields" marker
/// rather than repurposing an unrelated payload type.
private struct EmptyEncodable: Encodable, Sendable {}

public enum InstrumentJobSyncError: Error {
    case noDeviceToken
    case instrumentJobNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
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
                staffUsernames: dto.staffUsernames
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
                staffOnly: columnDTO.staffOnly
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

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID`.
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
        try modelContext.save()
    }
}
