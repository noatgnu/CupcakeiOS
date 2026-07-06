import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Online-only — the metadata-merge signal this whole flow exists for is server-side and
/// synchronous, so there's no meaningful "queue for later" offline path the way other creates
/// have (see `AnnotationDataRequest`'s established shortcut, reused here from `StepAnnotation`).
/// Depends on `InstrumentJobSyncService` to refresh the job's merged metadata table afterward,
/// since that service already owns the `MetadataTable` upsert logic.
public actor InstrumentJobAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let instrumentJobSync: InstrumentJobSyncService
    private let store: InstrumentJobAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?,
        instrumentJobSync: InstrumentJobSyncService
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.instrumentJobSync = instrumentJobSync
        self.store = InstrumentJobAnnotationStore(modelContainer: modelContainer)
    }

    public func refetchAnnotations(jobServerID: Int64, jobClientID: UUID) async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<InstrumentJobAnnotationDTO> = try await apiClient.get(
            "instrument-job-annotations/?instrument_job=\(jobServerID)",
            authorizationHeader: authorization
        )
        while true {
            try await store.upsert(page.results, jobClientID: jobClientID)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Sets the job's `instrument` FK, then the full 3-call booking sequence (`POST
    /// instrument-usage/` -> `POST instrument-job-annotations/` with `annotation_type: "booking"`
    /// -> `POST instrument-usage-job-annotations/` to link them), then refreshes the job's
    /// metadata table to pick up whatever the server-side merge signal added. Requires the job to
    /// already have a `metadata_table` (via `createMetadataFromTemplate`) — the merge signal
    /// no-ops otherwise.
    ///
    /// The `instrument` PATCH is not optional — confirmed live that the merge signal
    /// (`ccm/signals.py:175-260`) bails out immediately if `instrument_job.instrument` is unset,
    /// regardless of whether the usage/annotation/link calls below all succeed. Without it, this
    /// whole method silently does nothing but create bookkeeping records — no error, no merged
    /// columns, and no indication anything is wrong.
    @discardableResult
    public func createBookingAnnotation(
        jobServerID: Int64,
        jobClientID: UUID,
        instrumentServerID: Int64,
        instrumentName: String,
        timeStarted: String,
        timeEnded: String?,
        usageDescription: String
    ) async throws -> MetadataTableDTO? {
        guard let token = deviceToken() else {
            throw InstrumentJobAnnotationSyncError.noDeviceToken
        }
        let authorization = "DeviceToken \(token)"

        try await instrumentJobSync.updateInstrument(jobServerID: jobServerID, instrumentServerID: instrumentServerID)

        let usage: InstrumentUsageDTO = try await apiClient.send(
            "instrument-usage/",
            method: .post,
            body: CreateInstrumentUsageRequest(
                instrument: instrumentServerID,
                timeStarted: timeStarted,
                timeEnded: timeEnded,
                description: usageDescription,
                maintenance: false
            ),
            authorizationHeader: authorization
        )

        let annotationText = "Instrument booking for \(instrumentName)"
        let annotation: InstrumentJobAnnotationDTO = try await apiClient.send(
            "instrument-job-annotations/",
            method: .post,
            body: CreateInstrumentJobAnnotationRequest(
                instrumentJob: jobServerID,
                annotationData: AnnotationDataRequest(annotationType: "booking", annotation: annotationText)
            ),
            authorizationHeader: authorization
        )

        _ = try await apiClient.send(
            "instrument-usage-job-annotations/",
            method: .post,
            body: CreateInstrumentUsageJobAnnotationRequest(instrumentJobAnnotation: annotation.id, instrumentUsage: usage.id),
            authorizationHeader: authorization
        ) as InstrumentUsageJobAnnotationDTO

        try await store.upsertSingle(annotation, jobClientID: jobClientID, instrumentUsageServerID: usage.id)

        return try await instrumentJobSync.refreshMetadataTable(jobServerID: jobServerID, jobClientID: jobClientID)
    }
}

public enum InstrumentJobAnnotationSyncError: Error {
    case noDeviceToken
}

@ModelActor
actor InstrumentJobAnnotationStore {
    func upsert(_ dtos: [InstrumentJobAnnotationDTO], jobClientID: UUID) throws {
        for dto in dtos {
            upsert(dto, jobClientID: jobClientID, instrumentUsageServerID: nil)
        }
        try modelContext.save()
    }

    func upsertSingle(_ dto: InstrumentJobAnnotationDTO, jobClientID: UUID, instrumentUsageServerID: Int64?) throws {
        upsert(dto, jobClientID: jobClientID, instrumentUsageServerID: instrumentUsageServerID)
        try modelContext.save()
    }

    private func upsert(_ dto: InstrumentJobAnnotationDTO, jobClientID: UUID, instrumentUsageServerID: Int64?) {
        let annotationServerID = dto.id
        let existing = try? modelContext.fetch(
            FetchDescriptor<CachedInstrumentJobAnnotation>(predicate: #Predicate { $0.serverID == annotationServerID })
        )
        let annotation = existing?.first ?? {
            let created = CachedInstrumentJobAnnotation(serverID: dto.id, instrumentJobClientID: jobClientID)
            modelContext.insert(created)
            return created
        }()
        annotation.annotationText = dto.annotationText
        annotation.annotationType = dto.annotationType
        annotation.role = dto.role
        annotation.order = dto.order
        if let instrumentUsageServerID {
            annotation.instrumentUsageServerID = instrumentUsageServerID
        }
    }
}
