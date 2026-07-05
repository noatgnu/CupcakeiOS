import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Text annotations are always created locally first (`createTextAnnotation`) — so nothing is
/// lost or blocked on the network — then synced immediately via `syncLocallyCreatedTextAnnotation`
/// when both the session and step it's attached to have a `serverID`; the caller (see
/// `SessionDetailView`) queues a genuine-unreachability failure in the outbox, same
/// create-locally-then-sync-or-queue pattern as protocol/section/step/session/step-reagent
/// creation. Uses the `annotation_data` shortcut so the client never has to create the
/// underlying `Annotation` row itself. File-bearing annotation types (photo/audio/video/sketch)
/// go through chunked upload instead — not this path, and not in scope until later phases.
public actor StepAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: StepAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = StepAnnotationStore(modelContainer: modelContainer)
    }

    @discardableResult
    public func createTextAnnotation(sessionClientID: UUID, stepClientID: UUID, text: String) async throws -> UUID {
        try await store.insertLocalOnly(sessionClientID: sessionClientID, stepClientID: stepClientID, text: text)
    }

    /// Pushes an *already locally-created* annotation to the server, attaching the new
    /// `serverID` to that same local record instead of creating a duplicate — the
    /// create-locally-then-sync path used when signed in, and what `OutboxService.replay(_:)`
    /// calls to retry a queued `createTextAnnotation` entry. Throws
    /// `SyncDependencyError.parentNotSynced` if either the session or the step hasn't synced yet.
    @discardableResult
    public func syncLocallyCreatedTextAnnotation(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw StepAnnotationSyncError.noDeviceToken
        }
        let fields = try await store.annotationFields(clientID: clientID)
        guard let sessionServerID = fields.sessionServerID, let stepServerID = fields.stepServerID else {
            throw SyncDependencyError.parentNotSynced
        }
        let dto: StepAnnotationDTO = try await apiClient.send(
            "step-annotations/",
            method: .post,
            body: CreateStepAnnotationRequest(
                session: sessionServerID,
                step: stepServerID,
                annotationData: AnnotationDataRequest(annotationType: "text", annotation: fields.text)
            ),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }
}

public enum StepAnnotationSyncError: Error {
    case noDeviceToken
    case annotationNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor StepAnnotationStore {
    func insertLocalOnly(sessionClientID: UUID, stepClientID: UUID, text: String) throws -> UUID {
        let cached = CachedStepAnnotation(
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationText: text,
            annotationType: "text",
            order: 0
        )
        modelContext.insert(cached)
        try modelContext.save()
        return cached.clientID
    }

    func annotationFields(clientID: UUID) throws -> (sessionServerID: Int64?, stepServerID: Int64?, text: String) {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        let sessionClientID = annotation.sessionClientID
        let sessionMatch = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == sessionClientID })
        ).first
        let stepClientID = annotation.stepClientID
        let stepMatch = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first
        return (sessionMatch?.serverID, stepMatch?.serverID, annotation.annotationText)
    }

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID` —
    /// the record already exists (created locally first), so this updates it in place rather
    /// than inserting a second copy.
    func attachServerID(clientID: UUID, dto: StepAnnotationDTO) throws {
        guard let annotation = try modelContext.fetch(
            FetchDescriptor<CachedStepAnnotation>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw StepAnnotationSyncError.annotationNotCached
        }
        annotation.serverID = dto.id
        annotation.annotationText = dto.annotationText
        annotation.annotationType = dto.annotationType
        annotation.order = dto.order
        try modelContext.save()
    }
}
