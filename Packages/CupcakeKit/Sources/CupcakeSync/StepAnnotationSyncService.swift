import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Online-create for the simplest annotation type (plain text), using the `annotation_data`
/// shortcut so the client never has to create the underlying `Annotation` row itself — falling
/// back to a purely local insert when either there's no stored `DeviceToken` or the session/step
/// being annotated has no `serverID` yet (standalone mode, or a session/step not yet synced).
/// File-bearing annotation types (photo/audio/video/sketch) go through chunked upload instead —
/// not this path, and not in scope until later phases.
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
        if let token = deviceToken(),
           let (sessionServerID, stepServerID) = try await store.serverIdentifiers(sessionClientID: sessionClientID, stepClientID: stepClientID) {
            let dto: StepAnnotationDTO = try await apiClient.send(
                "step-annotations/",
                method: .post,
                body: CreateStepAnnotationRequest(
                    session: sessionServerID,
                    step: stepServerID,
                    annotationData: AnnotationDataRequest(annotationType: "text", annotation: text)
                ),
                authorizationHeader: "DeviceToken \(token)"
            )
            return try await store.insert(fromServer: dto, sessionClientID: sessionClientID, stepClientID: stepClientID)
        }
        return try await store.insertLocalOnly(sessionClientID: sessionClientID, stepClientID: stepClientID, text: text)
    }
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor StepAnnotationStore {
    /// Both the session and the step need a `serverID` for the online path to make sense —
    /// either being locally-only (standalone mode, or not yet synced) forces the local-only path.
    func serverIdentifiers(sessionClientID: UUID, stepClientID: UUID) throws -> (Int64, Int64)? {
        let sessionMatch = try modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.clientID == sessionClientID })
        ).first
        let stepMatch = try modelContext.fetch(
            FetchDescriptor<CachedProtocolStep>(predicate: #Predicate { $0.clientID == stepClientID })
        ).first
        guard let sessionServerID = sessionMatch?.serverID, let stepServerID = stepMatch?.serverID else {
            return nil
        }
        return (sessionServerID, stepServerID)
    }

    func insert(fromServer dto: StepAnnotationDTO, sessionClientID: UUID, stepClientID: UUID) throws -> UUID {
        let cached = CachedStepAnnotation(
            serverID: dto.id,
            sessionClientID: sessionClientID,
            stepClientID: stepClientID,
            annotationText: dto.annotationText,
            annotationType: dto.annotationType,
            order: dto.order
        )
        modelContext.insert(cached)
        try modelContext.save()
        return cached.clientID
    }

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
}
