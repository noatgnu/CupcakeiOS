import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Phase 1: full-refetch, read-only population only. Offline create, plus the
/// `create_metadata_table`/`add_metadata_column` ontology-tagging actions, land in Phase 4.
public actor SessionAnnotationSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: SessionAnnotationStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = SessionAnnotationStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<SessionAnnotationDTO> = try await apiClient.get(
            "session-annotations/",
            authorizationHeader: authorization
        )
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor SessionAnnotationStore {
    func upsert(_ dtos: [SessionAnnotationDTO]) throws {
        for dto in dtos {
            // A session-annotation fetched from a list endpoint may reference a session this
            // device hasn't cached yet (e.g. one it doesn't own but can see via lab-group
            // access) — skip rather than crash; it'll resolve once that session syncs too.
            guard let sessionClientID = sessionClientID(forServerID: dto.session) else { continue }

            let annotationID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedSessionAnnotation>(predicate: #Predicate { $0.serverID == annotationID })
            )
            let annotation = existing?.first ?? {
                let created = CachedSessionAnnotation(
                    serverID: dto.id,
                    sessionClientID: sessionClientID,
                    annotationText: dto.annotationText,
                    annotationType: dto.annotationType,
                    order: dto.order
                )
                modelContext.insert(created)
                return created
            }()
            annotation.sessionClientID = sessionClientID
            annotation.annotationText = dto.annotationText
            annotation.annotationType = dto.annotationType
            annotation.order = dto.order
        }
        try modelContext.save()
    }

    private func sessionClientID(forServerID sessionServerID: Int64) -> UUID? {
        let match = try? modelContext.fetch(
            FetchDescriptor<CachedSession>(predicate: #Predicate { $0.serverID == sessionServerID })
        )
        return match?.first?.clientID
    }
}
