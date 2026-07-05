import CupcakeModels
import CupcakeNetworking
import Foundation
import SwiftData

/// Read-sync + create-locally-then-sync-or-queue for `Project` — same shape as
/// `ProtocolSyncService`. Part of the `InstrumentJob` subsystem (Phase 4.5).
public actor ProjectSyncService {
    private let apiClient: APIClient
    private let deviceToken: @Sendable () -> String?
    private let store: ProjectStore

    public init(
        modelContainer: ModelContainer,
        apiClient: APIClient,
        deviceToken: @escaping @Sendable () -> String?
    ) {
        self.apiClient = apiClient
        self.deviceToken = deviceToken
        self.store = ProjectStore(modelContainer: modelContainer)
    }

    public func refetchAll() async throws {
        guard let token = deviceToken() else { return }
        let authorization = "DeviceToken \(token)"

        var page: PaginatedResponse<ProjectDTO> = try await apiClient.get("projects/", authorizationHeader: authorization)
        while true {
            try await store.upsert(page.results)
            guard let nextURLString = page.next, let nextURL = URL(string: nextURLString) else { break }
            page = try await apiClient.get(absoluteURL: nextURL, authorizationHeader: authorization)
        }
    }

    /// Pushes an *already locally-created* project to the server, attaching the new `serverID`
    /// to that same local record — the create-locally-then-sync path used when signed in, and
    /// what `OutboxService.replay(_:)` calls to retry a queued `createProject` entry.
    @discardableResult
    public func syncLocallyCreatedProject(clientID: UUID) async throws -> Int64 {
        guard let token = deviceToken() else {
            throw ProjectSyncError.noDeviceToken
        }
        let fields = try await store.projectFields(clientID: clientID)
        let dto: ProjectDTO = try await apiClient.send(
            "projects/",
            method: .post,
            body: CreateProjectRequest(projectName: fields.projectName, projectDescription: fields.projectDescription),
            authorizationHeader: "DeviceToken \(token)"
        )
        try await store.attachServerID(clientID: clientID, dto: dto)
        return dto.id
    }
}

public enum ProjectSyncError: Error {
    case noDeviceToken
    case projectNotCached
}

/// SwiftData access is isolated to this `@ModelActor` — see `ProtocolStore`'s doc comment for why.
@ModelActor
actor ProjectStore {
    func upsert(_ dtos: [ProjectDTO]) throws {
        for dto in dtos {
            let projectServerID = dto.id
            let existing = try? modelContext.fetch(
                FetchDescriptor<CachedProject>(predicate: #Predicate { $0.serverID == projectServerID })
            )
            let project = existing?.first ?? {
                let created = CachedProject(serverID: dto.id, projectName: dto.projectName, projectDescription: dto.projectDescription)
                modelContext.insert(created)
                return created
            }()
            project.projectName = dto.projectName
            project.projectDescription = dto.projectDescription
        }
        try modelContext.save()
    }

    func projectFields(clientID: UUID) throws -> (projectName: String, projectDescription: String?) {
        guard let project = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProjectSyncError.projectNotCached
        }
        return (project.projectName, project.projectDescription)
    }

    /// Attaches a newly-assigned `serverID` to the existing local record matched by `clientID` —
    /// the record already exists (created locally first), so this updates it in place rather
    /// than inserting a second copy.
    func attachServerID(clientID: UUID, dto: ProjectDTO) throws {
        guard let project = try modelContext.fetch(
            FetchDescriptor<CachedProject>(predicate: #Predicate { $0.clientID == clientID })
        ).first else {
            throw ProjectSyncError.projectNotCached
        }
        project.serverID = dto.id
        project.projectName = dto.projectName
        project.projectDescription = dto.projectDescription
        try modelContext.save()
    }
}
